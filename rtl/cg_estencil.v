module cg_estencil #(
    parameter NG     = 8,
    parameter WV     = 32,
    parameter FV     = 24,
    parameter LOGNG  = $clog2(NG),
    parameter LOGN   = 2*LOGNG
)(
    input  wire                 clk,
    input  wire                 rst,
    input  wire                 ld_b_we,
    input  wire [LOGN-1:0]      ld_b_addr,
    input  wire signed [WV-1:0] ld_b_data,
    input  wire                 start,
    input  wire [15:0]          maxit,
    input  wire [6:0]           tolsh,
    output reg                  done,
    output wire                 busy,
    output reg                  conv,
    output reg                  nc,
    output reg                  stag,
    output reg                  err,
    output reg  [15:0]          iters,
    output reg  [31:0]          cycles,
    input  wire [LOGN-1:0]      x_addr,
    output wire signed [WV-1:0] x_data
);
    localparam N    = NG * NG;
    localparam FA   = 2;
    localparam ACCW = 2*WV + LOGN + 2;
    localparam XW   = ACCW + FV + 1;
    localparam KW   = $clog2(ACCW);
    localparam MR   = (WV > 18) ? WV : 18;
    localparam signed [WV-1:0] VMAX = {1'b0, {(WV-1){1'b1}}};
    localparam signed [WV-1:0] VMIN = {1'b1, {(WV-1){1'b0}}};

    localparam [3:0] S_IDLE = 0, S_INIT = 2, S_RINIT = 3, S_AP = 4, S_APD = 5,
                     S_SIG = 6, S_RSIG = 7, S_DIV = 8, S_UPD = 9, S_RUPD = 10, S_PUPD = 11, S_DONE = 12;
    localparam [3:0] M_AP = 0, M_DR = 1, M_RR = 2, M_RZ = 3, M_PQ = 4, M_AQ = 5, M_APV = 6,
                     M_DRN = 7, M_RNRN = 8, M_RNZN = 9, M_BP = 10;

    function signed [WV-1:0] sat_acc;
        input signed [ACCW-1:0] v;
        begin
            if (v > $signed({{(ACCW-WV){1'b0}}, VMAX}))      sat_acc = VMAX;
            else if (v < $signed({{(ACCW-WV){1'b1}}, VMIN})) sat_acc = VMIN;
            else                                             sat_acc = v[WV-1:0];
        end
    endfunction
    function signed [WV-1:0] sat_w1;
        input signed [WV:0] v;
        begin
            if (v > $signed({1'b0, VMAX}))      sat_w1 = VMAX;
            else if (v < $signed({1'b1, VMIN})) sat_w1 = VMIN;
            else                                sat_w1 = v[WV-1:0];
        end
    endfunction
    function signed [WV-1:0] mulfin;
        input signed [2*WV-1:0] pr;
        reg signed [2*WV:0] t;
        begin
            t = ($signed({pr[2*WV-1], pr}) + $signed({{(2*WV-FV+1){1'b0}}, 1'b1, {(FV-1){1'b0}}})) >>> FV;
            if (t > $signed({{(WV+1){1'b0}}, VMAX}))      mulfin = VMAX;
            else if (t < $signed({{(WV+1){1'b1}}, VMIN})) mulfin = VMIN;
            else                                          mulfin = t[WV-1:0];
        end
    endfunction

    reg [3:0]           state;
    reg [2:0]           ph;
    reg [LOGN-1:0]      k;
    reg [LOGN-1:0]      rb;
    reg [2:0]           j;
    reg [15:0]          it, maxit_r;
    reg [6:0]           tolsh_r;
    reg signed [ACCW-1:0] rho, thr, rhon, dnum, dden;
    reg                 tgt;
    reg [KW-1:0]        ksh;
    reg signed [WV-1:0] dn, nn, alpha, beta;
    reg signed [2*WV-1:0] sprod;
    reg                 v1, v2, f1, f2, l1, l2;
    reg [LOGN-1:0]      rb1, rb2;
    reg signed [5:0]    w1;

    assign busy = (state != S_IDLE);

    wire [LOGNG-1:0] fila = rb[LOGN-1:LOGNG];
    wire [LOGNG-1:0] col  = rb[LOGNG-1:0];
    reg  [LOGN-1:0]  nb_addr;
    reg  signed [5:0] nb_w;
    always @* begin
        nb_addr = rb; nb_w = 6'sd16;
        case (j)
            3'd1: begin nb_addr = rb - 1'b1;            nb_w = (col  != 0)      ? -6'sd4 : 6'sd0; end
            3'd2: begin nb_addr = rb + 1'b1;            nb_w = (col  != NG - 1) ? -6'sd4 : 6'sd0; end
            3'd3: begin nb_addr = rb - NG[LOGN-1:0];    nb_w = (fila != 0)      ? -6'sd4 : 6'sd0; end
            3'd4: begin nb_addr = rb + NG[LOGN-1:0];    nb_w = (fila != NG - 1) ? -6'sd4 : 6'sd0; end
            default: ;
        endcase
    end

    reg                  rec_start;
    reg  signed [WV-1:0] rec_d;
    wire                 rec_done, rec_sing, rec_busy;
    wire signed [WV-1:0] rec_r;
    recip_nr #(.W(WV), .F(FV), .K(6), .M(MR), .ITERS(2)) u_rec (
        .clk(clk), .rst(rst), .start(rec_start), .d(rec_d),
        .done(rec_done), .r(rec_r), .sing(rec_sing), .busy(rec_busy));

    reg [KW-1:0] bl_c;
    integer bi;
    always @* begin
        bl_c = 0;
        for (bi = 0; bi < ACCW; bi = bi + 1)
            if (dden[bi]) bl_c = bi;
    end
    wire [ACCW-1:0] sh_in = (ph == 3'd1) ? dden : dnum;
    wire [XW:0]     sh_x2 = {1'b0, sh_in, {(FV+1){1'b0}}};
    wire [XW:0]     sh_y  = sh_x2 >> ksh;
    wire [XW:0]     sh_r  = (sh_y + 1'b1) >> 1;
    wire signed [WV-1:0] sh_sat = (sh_r > {{(XW+1-WV){1'b0}}, VMAX}) ? VMAX : sh_r[WV-1:0];
    wire signed [WV-1:0] div_res = mulfin(sprod);

    reg [LOGN-1:0] vra;
    reg [3:0]      mop;
    reg accA_en, accA_first, accB_en, accB_first;
    reg rn_en, xn_en, zn_en;
    reg r_we_u, x_we_g, x_zero, p_we_g, p_init;
    always @* begin
        vra = k; mop = M_AP;
        accA_en = v2; accA_first = f2; accB_en = 1'b0; accB_first = 1'b0;
        rn_en = 1'b0; xn_en = 1'b0; zn_en = 1'b0;
        r_we_u = 1'b0; x_we_g = 1'b0; x_zero = 1'b0; p_we_g = 1'b0; p_init = 1'b0;
        case (state)
            S_IDLE: vra = x_addr;
            S_INIT: begin
                case (ph)
                    3'd1: mop = M_DR;
                    3'd2: begin mop = M_RR; zn_en = 1'b1; end
                    3'd3: begin mop = M_RZ; accB_en = 1'b1; accB_first = (k == 0);
                                x_we_g = 1'b1; x_zero = 1'b1; p_we_g = 1'b1; p_init = 1'b1; end
                    3'd4: begin accA_en = 1'b1; accA_first = (k == 0); end
                    default: ;
                endcase
            end
            S_AP:  vra = nb_addr;
            S_SIG: begin
                if (ph == 3'd1) mop = M_PQ;
                if (ph == 3'd2) begin accA_en = 1'b1; accA_first = (k == 0); end
            end
            S_UPD: begin
                case (ph)
                    3'd1: mop = M_AQ;
                    3'd2: begin mop = M_APV; rn_en = 1'b1; end
                    3'd3: begin mop = M_DRN; xn_en = 1'b1; r_we_u = 1'b1; end
                    3'd4: begin mop = M_RNRN; zn_en = 1'b1; x_we_g = 1'b1; end
                    3'd5: begin mop = M_RNZN; accB_en = 1'b1; accB_first = (k == 0); end
                    3'd6: begin accA_en = 1'b1; accA_first = (k == 0); end
                    default: ;
                endcase
            end
            S_PUPD: begin
                if (ph == 3'd1) mop = M_BP;
                if (ph == 3'd2) p_we_g = 1'b1;
            end
            default: ;
        endcase
    end

    wire signed [WV-1:0] x_rd, r_rd, p_rd, q_rd;
    reg  signed [2*WV-1:0] prod;
    reg  signed [ACCW-1:0] accA, accB;
    reg  signed [WV-1:0] rn, zn, xn;
    localparam signed [WV-1:0] ONE = 1 <<< FV;

    wire signed [WV-1:0] mf   = mulfin(prod);
    wire signed [WV-1:0] rn_c = sat_w1($signed({r_rd[WV-1], r_rd}) - $signed({mf[WV-1], mf}));
    wire signed [WV-1:0] xn_c = sat_w1($signed({x_rd[WV-1], x_rd}) + $signed({mf[WV-1], mf}));
    wire signed [WV-1:0] pn_c = sat_w1($signed({r_rd[WV-1], r_rd}) + $signed({mf[WV-1], mf}));
    wire signed [ACCW-1:0] prod_x = prod;
    wire signed [ACCW-1:0] accA_n = (accA_first ? {ACCW{1'b0}} : accA) + prod_x;
    wire signed [ACCW-1:0] accB_n = (accB_first ? {ACCW{1'b0}} : accB) + prod_x;
    wire signed [ACCW-1:0] qacc   = (accA_n + $signed({{(ACCW-FA){1'b0}}, 1'b1, {(FA-1){1'b0}}})) >>> FA;
    wire signed [WV-1:0]   qv     = sat_acc(qacc);

    reg signed [WV-1:0] opa, opb;
    always @* begin
        case (mop)
            M_AP:    begin opa = w1;    opb = p_rd; end
            M_DR:    begin opa = ONE;   opb = r_rd; end
            M_RR:    begin opa = r_rd;  opb = r_rd; end
            M_RZ:    begin opa = r_rd;  opb = zn;   end
            M_PQ:    begin opa = p_rd;  opb = q_rd; end
            M_AQ:    begin opa = alpha; opb = q_rd; end
            M_APV:   begin opa = alpha; opb = p_rd; end
            M_DRN:   begin opa = ONE;   opb = rn;   end
            M_RNRN:  begin opa = rn;    opb = rn;   end
            M_RNZN:  begin opa = rn;    opb = zn;   end
            default: begin opa = beta;  opb = p_rd; end
        endcase
    end

    always @(posedge clk) begin
        prod <= opa * opb;
        if (accA_en) accA <= accA_n;
        if (accB_en) accB <= accB_n;
        if (rn_en) rn <= rn_c;
        if (xn_en) xn <= xn_c;
        if (zn_en) zn <= mf;
    end

    assign x_data = x_rd;
    wire idle = (state == S_IDLE);
    kry_ram #(.DW(WV), .AW(LOGN)) u_r (.clk(clk),
        .we(idle ? ld_b_we : r_we_u), .wa(idle ? ld_b_addr : k),
        .wd(idle ? ld_b_data : rn), .ra(vra), .rd(r_rd));
    kry_ram #(.DW(WV), .AW(LOGN)) u_x (.clk(clk),
        .we(x_we_g), .wa(k), .wd(x_zero ? {WV{1'b0}} : xn), .ra(vra), .rd(x_rd));
    kry_ram #(.DW(WV), .AW(LOGN)) u_p (.clk(clk),
        .we(p_we_g), .wa(k), .wd(p_init ? zn : pn_c), .ra(vra), .rd(p_rd));
    kry_ram #(.DW(WV), .AW(LOGN)) u_q (.clk(clk),
        .we(v2 && l2), .wa(rb2), .wd(qv), .ra(vra), .rd(q_rd));

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE; ph <= 0; k <= 0; rb <= 0; j <= 0; it <= 0;
            done <= 1'b0; conv <= 1'b0; nc <= 1'b0; stag <= 1'b0; err <= 1'b0;
            iters <= 0; cycles <= 0; rec_start <= 1'b0; rec_d <= 0;
            v1 <= 1'b0; v2 <= 1'b0; f1 <= 1'b0; f2 <= 1'b0; l1 <= 1'b0; l2 <= 1'b0;
            rb1 <= 0; rb2 <= 0; w1 <= 0;
            maxit_r <= 0; tolsh_r <= 0; tgt <= 1'b0; ksh <= 0;
            rho <= 0; thr <= 0; rhon <= 0; dnum <= 0; dden <= 0;
            dn <= 0; nn <= 0; alpha <= 0; beta <= 0; sprod <= 0;
        end else begin
            done <= 1'b0;
            rec_start <= 1'b0;
            if (state != S_IDLE) cycles <= cycles + 1'b1;

            v1 <= (state == S_AP); f1 <= (j == 0); l1 <= (j == 3'd4); rb1 <= rb; w1 <= nb_w;
            v2 <= v1; f2 <= f1; l2 <= l1; rb2 <= rb1;

            case (state)
                S_IDLE: if (start) begin
                    maxit_r <= maxit; tolsh_r <= tolsh;
                    conv <= 1'b0; nc <= 1'b0; stag <= 1'b0; err <= 1'b0;
                    it <= 0; iters <= 0; cycles <= 0; ph <= 0; k <= 0;
                    state <= S_INIT;
                end
                S_INIT: begin
                    if (ph == 3'd4) begin
                        ph <= 0; k <= k + 1'b1;
                        if (k == N - 1) state <= S_RINIT;
                    end else ph <= ph + 1'b1;
                end
                S_RINIT: begin
                    rho <= accA; thr <= accB >>> tolsh_r;
                    if (accB == 0) begin conv <= 1'b1; state <= S_DONE; end
                    else begin state <= S_AP; rb <= 0; j <= 0; end
                end
                S_AP: begin
                    if (j == 3'd4) begin
                        j <= 0; rb <= rb + 1'b1;
                        if (rb == N - 1) state <= S_APD;
                    end else j <= j + 1'b1;
                end
                S_APD: if (!v1 && !v2) begin state <= S_SIG; k <= 0; ph <= 0; end
                S_SIG: begin
                    if (ph == 3'd2) begin
                        ph <= 0; k <= k + 1'b1;
                        if (k == N - 1) state <= S_RSIG;
                    end else ph <= ph + 1'b1;
                end
                S_RSIG: begin
                    if (accA <= 0) begin
                        if (it == 0) err <= 1'b1; else stag <= 1'b1;
                        state <= S_DONE;
                    end
                    else begin dnum <= rho; dden <= accA; tgt <= 1'b0; ph <= 0; state <= S_DIV; end
                end
                S_DIV: begin
                    case (ph)
                        3'd0: begin ksh <= bl_c; ph <= 3'd1; end
                        3'd1: begin dn <= sh_sat; ph <= 3'd2; end
                        3'd2: begin nn <= sh_sat; rec_start <= 1'b1; rec_d <= dn; ph <= 3'd3; end
                        3'd3: if (rec_done) begin sprod <= nn * rec_r; ph <= 3'd4; end
                        default: begin
                            ph <= 0; k <= 0;
                            if (!tgt) begin alpha <= div_res; state <= S_UPD; end
                            else begin beta <= div_res; rho <= rhon; state <= S_PUPD; end
                        end
                    endcase
                end
                S_UPD: begin
                    if (ph == 3'd6) begin
                        ph <= 0; k <= k + 1'b1;
                        if (k == N - 1) state <= S_RUPD;
                    end else ph <= ph + 1'b1;
                end
                S_RUPD: begin
                    rhon <= accA; it <= it + 1'b1; iters <= it + 1'b1;
                    if (accB == 0 || accB < thr) begin conv <= 1'b1; state <= S_DONE; end
                    else if (it + 1'b1 == maxit_r) begin nc <= 1'b1; state <= S_DONE; end
                    else if (accA == 0) begin stag <= 1'b1; state <= S_DONE; end
                    else begin dnum <= accA; dden <= rho; tgt <= 1'b1; ph <= 0; state <= S_DIV; end
                end
                S_PUPD: begin
                    if (ph == 3'd2) begin
                        ph <= 0; k <= k + 1'b1;
                        if (k == N - 1) begin state <= S_AP; rb <= 0; j <= 0; end
                    end else ph <= ph + 1'b1;
                end
                S_DONE: begin done <= 1'b1; state <= S_IDLE; end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule

module kry_ram #(parameter DW = 18, parameter AW = 4)(
    input  wire          clk,
    input  wire          we,
    input  wire [AW-1:0] wa,
    input  wire [DW-1:0] wd,
    input  wire [AW-1:0] ra,
    output reg  [DW-1:0] rd
);
    reg [DW-1:0] m [0:(1<<AW)-1];
    always @(posedge clk) begin
        if (we) m[wa] <= wd;
        rd <= m[ra];
    end
endmodule

