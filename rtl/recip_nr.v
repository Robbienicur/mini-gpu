module recip_nr #(
    parameter W = 18,
    parameter F = 12,
    parameter K = 6,
    parameter M = 18,
    parameter ITERS = 2
)(
    input  wire                clk,
    input  wire                rst,
    input  wire                start,
    input  wire signed [W-1:0] d,
    output reg                 done,
    output reg  signed [W-1:0] r,
    output reg                 sing,
    output wire                busy
);

    localparam LZW   = (W > 1) ? $clog2(W) : 1;
    localparam SHMIN = 2*F + 1 - M - W;
    localparam PL    = (SHMIN + W - 1 > 0) ? (SHMIN + W - 1) : 0;
    localparam QOFF  = PL - SHMIN;
    localparam QW    = $clog2(QOFF + 2);
    localparam YW    = M + PL + 1;
    localparam CW    = ((YW + 1 > W) ? (YW + 1) : W) + 1;

    localparam [3:0] S_IDLE = 4'd0, S_NORM = 4'd1, S_SEED = 4'd2, S_M1 = 4'd3,
                     S_T    = 4'd4, S_M2   = 4'd5, S_X    = 4'd6, S_FIN = 4'd7, S_OUT = 4'd8;

    function [63:0] lut_val;
        input integer idx;
        reg [63:0] num, dv, q, rem;
        integer i;
        begin
            dv  = 64'd1 << (K + 1);
            dv  = dv + 2 * idx + 1;
            num = (64'd1 << (M + K + 2)) + dv;
            dv  = dv << 1;
            q   = 64'd0;
            rem = 64'd0;
            for (i = 63; i >= 0; i = i - 1) begin
                rem = {rem[62:0], num[i]};
                if (rem >= dv) begin
                    rem  = rem - dv;
                    q[i] = 1'b1;
                end
            end
            lut_val = q - (64'd1 << (M - 1));
        end
    endfunction

    wire [(M-1)*(1<<K)-1:0] lut_flat;
    genvar gi;
    generate
        for (gi = 0; gi < (1 << K); gi = gi + 1) begin : g_lut
            localparam [63:0] LV = lut_val(gi);
            assign lut_flat[gi*(M-1) +: (M-1)] = LV[M-2:0];
        end
    endgenerate

    reg [3:0]           state;
    reg [W-1:0]         a_r;
    reg                 neg_r, zero_r;
    reg [LZW-1:0]       lz_r;
    reg [M-2:0]         ml_r;
    reg signed [M-1:0]  xl_r;
    reg signed [M-1:0]  ed_r;
    reg signed [2*M-1:0] p_r;
    reg [7:0]           it_r;
    reg [W-1:0]         rp_r;

    assign busy = (state != S_IDLE);

    reg [LZW-1:0] lz_c;
    integer bi;
    always @* begin
        lz_c = W - 1;
        for (bi = 0; bi < W; bi = bi + 1)
            if (a_r[bi]) lz_c = W - 1 - bi;
    end
    wire [W-1:0] n_c = a_r << lz_c;
    wire [M-1:0] mint_c;
    generate
        if (M >= W) begin : g_mext
            if (M > W) begin : g_pad
                assign mint_c = {n_c, {(M-W){1'b0}}};
            end else begin : g_eq
                assign mint_c = n_c;
            end
        end else begin : g_mtr
            assign mint_c = n_c[W-1 -: M];
        end
    endgenerate

    wire [K-1:0]   idx_c  = ml_r[M-2 -: K];
    wire [M-2:0]   seed_c = lut_flat[idx_c*(M-1) +: (M-1)];

    wire signed [M-1:0]   mb_c   = (state == S_M1) ? $signed({1'b0, ml_r}) : ed_r;
    wire signed [2*M-1:0] prod_c = xl_r * mb_c;

    wire [M-1:0] hm_c   = {1'b1, {(M-1){1'b0}}};
    wire [M-1:0] edn_c  = hm_c - {1'b0, ml_r} - xl_r - p_r[2*M-2:M-1];
    wire [M:0]   sh_c   = {ed_r[M-1], ed_r} + p_r[2*M-1:M-1];
    wire [M-1:0] xln_c  = xl_r + sh_c[M:1];

    wire [M-1:0]   x_c  = hm_c + xl_r;
    wire [QW-1:0]  q_c  = QOFF - lz_r;
    wire [YW-1:0]  y_c  = {x_c, {(PL+1){1'b0}}} >> q_c;
    wire [YW:0]    rv_c = ({1'b0, y_c} + 1'b1) >> 1;
    wire [CW-1:0]  rvx_c  = rv_c;
    wire [CW-1:0]  maxp_w = ({{(CW-1){1'b0}}, 1'b1} << (W - 1)) - 1'b1;
    wire [W-1:0]   rsat_c = (rvx_c > maxp_w) ? maxp_w[W-1:0] : rvx_c[W-1:0];

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            done  <= 1'b0;
            r     <= 0;
            sing  <= 1'b0;
            a_r <= 0; neg_r <= 1'b0; zero_r <= 1'b0; lz_r <= 0; ml_r <= 0;
            xl_r <= 0; ed_r <= 0; p_r <= 0; it_r <= 0; rp_r <= 0;
        end else begin
            done <= 1'b0;
            case (state)
                S_IDLE: if (start) begin
                    neg_r  <= d[W-1];
                    a_r    <= d[W-1] ? (~d + 1'b1) : d;
                    zero_r <= (d == 0);
                    state  <= S_NORM;
                end
                S_NORM: begin
                    lz_r  <= lz_c;
                    ml_r  <= mint_c[M-2:0];
                    state <= S_SEED;
                end
                S_SEED: begin
                    xl_r  <= $signed({1'b0, seed_c});
                    it_r  <= 0;
                    state <= (ITERS == 0) ? S_FIN : S_M1;
                end
                S_M1: begin p_r <= prod_c; state <= S_T;  end
                S_T:  begin ed_r <= edn_c[M-1:0]; state <= S_M2; end
                S_M2: begin p_r <= prod_c; state <= S_X;  end
                S_X:  begin
                    xl_r <= xln_c[M-1:0];
                    it_r <= it_r + 1'b1;
                    state <= (it_r == ITERS - 1) ? S_FIN : S_M1;
                end
                S_FIN: begin

                    rp_r  <= rsat_c;
                    state <= S_OUT;
                end
                S_OUT: begin
                    if (zero_r) begin
                        r    <= {1'b0, {(W-1){1'b1}}};
                        sing <= 1'b1;
                    end else begin
                        r    <= neg_r ? -$signed(rp_r) : $signed(rp_r);
                        sing <= 1'b0;
                    end
                    done  <= 1'b1;
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule

