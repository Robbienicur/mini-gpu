module inversa #(
    parameter N    = 128,
    parameter W    = 32,
    parameter F    = 20,
    parameter PAR  = 16,
    parameter PMIN = ((2*F - W + 1) > 0) ? (1 << (2*F - W + 1)) : 1,
    parameter DM   = 17
)(
    input  wire                clk,
    input  wire                rst,
    input  wire                start,
    input  wire [7:0]          n,
    output reg                 done,
    output wire                busy,
    output reg                 sing,
    output reg  [31:0]         cycles,
    output reg                 ovf,
    output wire                det_neg,
    output wire [DM-1:0]       det_m,
    output wire signed [15:0]  det_e,
    input  wire                ld_we,
    input  wire [7:0]          ld_row,
    input  wire [7:0]          ld_col,
    input  wire signed [W-1:0] ld_data,
    input  wire [7:0]          rd_row,
    input  wire [7:0]          rd_col,
    output wire signed [W-1:0] rd_data
);
    localparam NB   = N / PAR;
    localparam LP   = $clog2(PAR);
    localparam LNB  = $clog2(NB);
    localparam RW   = $clog2(N);
    localparam AW   = RW + LNB;
    localparam DEP  = N << LNB;
    localparam LW   = (LP > 0) ? LP : 1;
    localparam BW   = (LNB > 0) ? LNB : 1;
    localparam CW   = RW + 1;
    localparam ACW  = 2 * W + 2;
    localparam signed [W-1:0] ONE  = 1 <<< F;
    localparam signed [ACW-1:0] HALF = 1 <<< (F - 1);
    localparam signed [ACW-1:0] MAXP = (1 <<< (W - 1)) - 1;
    localparam signed [ACW-1:0] MINN = -(1 <<< (W - 1));

    localparam [1:0] MD_NORM = 2'd0, MD_UPD = 2'd1, MD_SCAN = 2'd2;

    localparam [3:0] S_IDLE = 4'd0, S_SCAN = 4'd1, S_DRAIN = 4'd2, S_PIV = 4'd3, S_RECW = 4'd4,
                     S_NORM = 4'd5, S_UPD0 = 4'd6, S_UPD = 4'd7, S_NEXT = 4'd8, S_FIN = 4'd9;

    function [BW-1:0] beat_of;
        input [7:0] j;
        begin
            beat_of = (LNB > 0) ? (j >> LP) : 0;
        end
    endfunction
    function [LW-1:0] lane_of;
        input [7:0] j;
        begin
            lane_of = (LP > 0) ? (j & ((1 << LP) - 1)) : 0;
        end
    endfunction

    reg [3:0]    state, after_drain;
    reg [1:0]    drain_cnt;
    reg [CW-1:0] p;
    reg [CW-1:0] ri;
    reg [CW-1:0] kb;
    reg [BW-1:0] bcur;
    reg [CW-1:0] nn;
    reg [CW-1:0] nbe;
    reg [RW-1:0] rowmap [0:N-1];
    reg [RW-1:0] invmap [0:N-1];
    integer      t;

    reg                cand_v;
    reg [W-1:0]        cand_abs;
    reg [RW-1:0]       cand_row;
    reg signed [W-1:0] cand_val;

    reg                rec_start;
    reg signed [W-1:0] rec_d;
    wire               rec_done, rec_sing, rec_busy;
    wire signed [W-1:0] rec_r;
    recip_nr #(.W(W), .F(F), .K(6), .M((W > 18) ? W : 18), .ITERS(2)) u_rec (
        .clk(clk), .rst(rst), .start(rec_start), .d(rec_d),
        .done(rec_done), .r(rec_r), .sing(rec_sing), .busy(rec_busy));

    assign busy = (state != S_IDLE);

    wire [BW-1:0] bp = beat_of(p);
    wire [LW-1:0] lp = lane_of(p);
    wire [CW-1:0] pn = p + 1'b1;
    wire [BW-1:0] bn = beat_of(pn);
    wire [LW-1:0] ln = lane_of(pn);

    reg          iss_v;
    reg [1:0]    iss_mode;
    reg [CW-1:0] iss_row;
    reg [BW-1:0] iss_b;
    reg          iss_first;
    always @* begin
        iss_v = 1'b0; iss_mode = MD_NORM; iss_row = ri; iss_b = bcur; iss_first = (kb == 0);
        case (state)
            S_SCAN: begin iss_v = 1'b1; iss_mode = MD_SCAN; iss_b = 0; iss_first = 1'b1; end
            S_NORM: begin iss_v = 1'b1; iss_mode = MD_NORM; iss_row = p; end
            S_UPD:  begin iss_v = 1'b1; iss_mode = MD_UPD; end
            default: ;
        endcase
    end
    wire [RW-1:0] iss_phys = rowmap[iss_row[RW-1:0]];
    wire [AW-1:0] iss_addr = (LNB > 0) ? {iss_phys, iss_b} : iss_phys;

    wire [RW-1:0] ex_phys = rowmap[rd_row[RW-1:0]];
    wire [RW-1:0] ex_col  = invmap[rd_col[RW-1:0]];
    wire [AW-1:0] ex_addr = (LNB > 0) ? {ex_phys, beat_of(ex_col)} : ex_phys;
    reg  [LW-1:0] ex_lane_q;
    always @(posedge clk) ex_lane_q <= lane_of(ex_col);

    wire [AW-1:0] ld_addr = (LNB > 0) ? {ld_row[RW-1:0], beat_of(ld_col)} : ld_row[RW-1:0];
    wire [LW-1:0] ld_lane = lane_of(ld_col);

    reg          v1, first1;  reg [1:0] mode1;  reg [CW-1:0] row1;  reg [BW-1:0] b1;  reg [AW-1:0] a1;
    reg          v2;          reg [1:0] mode2;  reg [CW-1:0] row2;  reg [BW-1:0] b2;  reg [AW-1:0] a2;
    reg          v3;          reg [1:0] mode3;  reg [CW-1:0] row3;  reg [BW-1:0] b3;  reg [AW-1:0] a3;
    reg signed [W-1:0] f_hold;

    wire [PAR*W-1:0] rdat;
    wire [PAR*W-1:0] prow_q;
    wire [PAR*W-1:0] res_flat;
    wire [PAR-1:0]   sat_flat;

    wire signed [W-1:0] a_lp = rdat[lp*W +: W];
    wire signed [W-1:0] f_c  = first1 ? a_lp : f_hold;

    wire          s3_we   = v3 && (mode3 != MD_SCAN);
    wire [AW-1:0] ram_wa  = busy ? a3 : ld_addr;
    wire [AW-1:0] ram_ra  = busy ? iss_addr : ex_addr;

    assign rd_data = rdat[ex_lane_q*W +: W];

    reg [PAR*W-1:0] prow_mem [0:NB-1];
    reg [PAR*W-1:0] prow_r;
    always @(posedge clk) begin
        if (v3 && mode3 == MD_NORM) prow_mem[b3] <= res_flat;
        prow_r <= prow_mem[iss_b];
    end
    assign prow_q = prow_r;

    genvar gl;
    generate
        for (gl = 0; gl < PAR; gl = gl + 1) begin : g_lane
            reg [W-1:0] bank [0:DEP-1];
            reg [W-1:0] q;
            wire we_l = busy ? s3_we : (ld_we && ld_lane == gl);
            wire [W-1:0] wd_l = busy ? res_flat[gl*W +: W] : ld_data;
            always @(posedge clk) begin
                if (we_l) bank[ram_wa] <= wd_l;
                q <= bank[ram_ra];
            end
            assign rdat[gl*W +: W] = q;

            wire signed [W-1:0] a_l   = rdat[gl*W +: W];
            wire                pcol  = (b1 == bp) && (gl == lp);
            wire signed [W-1:0] xs    = (mode1 == MD_UPD) ? f_c : (pcol ? ONE : a_l);
            wire signed [W-1:0] ys    = (mode1 == MD_UPD) ? $signed(prow_q[gl*W +: W]) : rec_r;
            wire signed [W-1:0] cs    = (mode1 == MD_UPD && !pcol) ? a_l : {W{1'b0}};
            reg  signed [W-1:0] x2, y2, c2;
            reg                 sub2;
            reg  signed [2*W-1:0] pr3;
            reg  signed [W-1:0]   c3;
            reg                   sub3;
            always @(posedge clk) begin
                x2 <= xs; y2 <= ys; c2 <= cs; sub2 <= (mode1 == MD_UPD);
                pr3 <= x2 * y2; c3 <= c2; sub3 <= sub2;
            end
            wire signed [ACW-1:0] cx  = c3;
            wire signed [ACW-1:0] px  = pr3;
            wire signed [ACW-1:0] acc = (cx <<< F) + (sub3 ? -px : px);
            wire signed [ACW-1:0] rnd = (acc + HALF) >>> F;
            wire signed [W-1:0]   sv  = (rnd > MAXP) ? MAXP[W-1:0] : (rnd < MINN) ? MINN[W-1:0] : rnd[W-1:0];
            assign res_flat[gl*W +: W] = sv;
            assign sat_flat[gl] = (rnd > MAXP) || (rnd < MINN);
        end
    endgenerate

    wire signed [W-1:0] res_ln = res_flat[ln*W +: W];

    always @(posedge clk) begin
        if (rst) begin
            v1 <= 1'b0; v2 <= 1'b0; v3 <= 1'b0;
        end else begin
            v1 <= iss_v; mode1 <= iss_mode; row1 <= iss_row; b1 <= iss_b; first1 <= iss_first; a1 <= iss_addr;
            v2 <= v1;    mode2 <= mode1;    row2 <= row1;    b2 <= b1;    a2 <= a1;
            v3 <= v2;    mode3 <= mode2;    row3 <= row2;    b3 <= b2;    a3 <= a2;
            if (v1 && mode1 == MD_UPD) f_hold <= f_c;
        end
    end

    wire               cs_scan = v1 && mode1 == MD_SCAN;
    wire               cs_upd  = v3 && mode3 == MD_UPD && (b3 == bn) && (pn < nn);
    wire               c_en    = cs_scan || cs_upd;
    wire [CW-1:0]      c_row   = cs_scan ? row1 : row3;
    wire signed [W-1:0] c_val  = cs_scan ? a_lp : res_ln;
    wire [CW-1:0]      c_tgt   = cs_scan ? p : pn;
    wire [W-1:0]       c_abs   = c_val[W-1] ? (~c_val + 1'b1) : c_val;
    wire               c_mayor = !cand_v || c_abs > cand_abs;
    wire               c_take  = (c_row >= c_tgt) && c_mayor;

    wire [RW-1:0] q_row   = cand_row;
    wire [RW-1:0] rm_p    = rowmap[p[RW-1:0]];
    wire [RW-1:0] rm_q    = rowmap[q_row];
    wire          piv_bad = (cand_abs < PMIN);
    wire [CW-1:0] ri_nx   = (ri + 1'b1 == p) ? ri + 2'd2 : ri + 1'b1;
    wire          ri_last = (ri == nn - 1) || ((ri == nn - 2) && (p == nn - 1));
    wire [7:0]    n_ok    = (n == 0 || n > N) ? N : n;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE; done <= 1'b0; sing <= 1'b0; cycles <= 0;
            p <= 0; ri <= 0; kb <= 0; bcur <= 0; drain_cnt <= 0; after_drain <= S_IDLE;
            nn <= N; nbe <= NB;
            cand_v <= 1'b0; cand_abs <= 0; cand_row <= 0; cand_val <= 0;
            rec_start <= 1'b0; rec_d <= 0; ovf <= 1'b0;
            for (t = 0; t < N; t = t + 1) begin rowmap[t] <= t; invmap[t] <= t; end
        end else begin
            done      <= 1'b0;
            rec_start <= 1'b0;
            if (state != S_IDLE) cycles <= cycles + 1'b1;

            if (s3_we && |sat_flat) ovf <= 1'b1;
            if (c_en && c_take) begin
                cand_v <= 1'b1; cand_abs <= c_abs; cand_row <= c_row[RW-1:0]; cand_val <= c_val;
            end

            case (state)
                S_IDLE: if (start) begin
                    for (t = 0; t < N; t = t + 1) begin rowmap[t] <= t; invmap[t] <= t; end
                    nn <= n_ok;
                    nbe <= (n_ok + PAR - 1) >> LP;
                    ovf <= 1'b0;
                    p <= 0; ri <= 0; sing <= 1'b0; cycles <= 0; cand_v <= 1'b0;
                    state <= S_SCAN;
                end
                S_SCAN: begin
                    ri <= ri + 1'b1;
                    if (ri == nn - 1) begin
                        drain_cnt <= 2'd0; after_drain <= S_PIV; state <= S_DRAIN;
                    end
                end
                S_DRAIN: begin
                    if (drain_cnt == 0) state <= after_drain;
                    else drain_cnt <= drain_cnt - 1'b1;
                end
                S_PIV: begin
                    if (piv_bad) begin
                        sing <= 1'b1; state <= S_FIN;
                    end else begin
                        rowmap[p[RW-1:0]] <= rm_q;  rowmap[q_row] <= rm_p;
                        invmap[rm_q] <= p[RW-1:0];  invmap[rm_p] <= q_row;
                        rec_d <= cand_val; rec_start <= 1'b1;
                        cand_v <= 1'b0;
                        state <= S_RECW;
                    end
                end
                S_RECW: if (rec_done) begin
                    bcur <= 0; kb <= 0; state <= S_NORM;
                end
                S_NORM: begin
                    bcur <= (bcur == nbe - 1) ? 0 : bcur + 1'b1;
                    if (kb == nbe - 1) begin
                        drain_cnt <= 2'd1; after_drain <= (nn == 1) ? S_NEXT : S_UPD0; state <= S_DRAIN;
                    end
                    kb <= kb + 1'b1;
                end
                S_UPD0: begin
                    ri <= (p == 0) ? 1 : 0; kb <= 0; bcur <= bp; state <= S_UPD;
                end
                S_UPD: begin
                    if (kb == nbe - 1) begin
                        kb <= 0; bcur <= bp;
                        if (ri_last) begin
                            drain_cnt <= 2'd1; after_drain <= S_NEXT; state <= S_DRAIN;
                        end else
                            ri <= ri_nx;
                    end else begin
                        kb <= kb + 1'b1;
                        bcur <= (bcur == nbe - 1) ? 0 : bcur + 1'b1;
                    end
                end
                S_NEXT: begin
                    if (p == nn - 1) state <= S_FIN;
                    else begin
                        p <= p + 1'b1;
                        state <= S_PIV;
                    end
                end
                S_FIN: begin
                    done <= 1'b1; state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end

    localparam QW = W + DM;
    reg [DM-1:0]          dm_r;
    reg signed [15:0]     de_r;
    reg                   dn_r, dv1, dv2, dv3;
    reg signed [QW:0]     dq;
    reg [QW-1:0]          dabs;
    reg [7:0]             db;
    wire signed [DM:0]    dm_s  = $signed({1'b0, dm_r});
    wire [QW-1:0]         d_izq = dabs << (QW - db);
    wire                  acepta = (state == S_PIV) && !piv_bad;
    function [7:0] blen;
        input [QW-1:0] v;
        reg [QW-1:0] sm, uno_alto;
        reg [7:0] k;
        integer b;
        begin
            sm = v;
            for (b = 0; (1 << b) < QW; b = b + 1) sm = sm | (sm >> (1 << b));
            uno_alto = sm ^ (sm >> 1);
            k = 0;
            for (b = 0; b < QW; b = b + 1) k = k | ({8{uno_alto[b]}} & (b + 1));
            blen = k;
        end
    endfunction
    always @(posedge clk) begin
        if (rst || (state == S_IDLE && start)) begin
            dm_r <= {1'b1, {(DM-1){1'b0}}};
            de_r <= -(DM - 1);
            dn_r <= 1'b0; dv1 <= 1'b0; dv2 <= 1'b0; dv3 <= 1'b0;
        end else begin
            dv1 <= acepta; dv2 <= dv1; dv3 <= dv2;
            if (acepta) begin
                dq   <= dm_s * cand_val;
                dn_r <= dn_r ^ cand_val[W-1] ^ (cand_row != p[RW-1:0]);
            end
            if (dv1) dabs <= dq[QW] ? -dq : dq;
            if (dv2) db <= blen(dabs);
            if (dv3) begin
                dm_r <= d_izq[QW-1 -: DM];
                de_r <= de_r + $signed({8'b0, db}) - DM - F;
            end
        end
    end
    assign det_neg = dn_r;
    assign det_m   = dm_r;
    assign det_e   = de_r;
endmodule
