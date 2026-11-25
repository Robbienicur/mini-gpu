module multiplica #(
    parameter NMAX = 128,
    parameter W    = 32,
    parameter F    = 20,
    parameter P    = 16
)(
    input  wire                clk,
    input  wire                reset,
    input  wire [7:0]          n,
    input  wire                wr_b,
    input  wire [7:0]          wr_fila,
    input  wire [7:0]          wr_col,
    input  wire signed [W-1:0] wr_dato,
    input  wire                start,
    input  wire [7:0]          fila,
    input  wire [7:0]          col0,
    output wire [7:0]          a_col,
    input  wire signed [W-1:0] a_dato,
    output reg                 done,
    output reg  [P*W-1:0]      C,
    output reg                 sat
);
    localparam LP  = $clog2(P);
    localparam RW  = $clog2(NMAX);
    localparam GW  = RW - LP;
    localparam ACW = 2 * W + RW + 1;
    localparam signed [ACW-1:0] MEDIO = 1 <<< (F - 1);
    localparam signed [ACW-1:0] MAXP  = (1 <<< (W - 1)) - 1;
    localparam signed [ACW-1:0] MINN  = -(1 <<< (W - 1));

    reg  [7:0] k;
    reg        corre, v1, v2, u1, u2, u3;
    wire       ultimo = corre && (k == n - 1);

    assign a_col = k;

    wire [RW+GW-1:0] dir_lee  = {k[RW-1:0], col0[RW-1:LP]};
    wire [RW+GW-1:0] dir_esc  = {wr_fila[RW-1:0], wr_col[RW-1:LP]};
    wire [LP-1:0]    carril_w = wr_col[LP-1:0];

    wire [P-1:0] sat_l;
    wire [P*W-1:0] res;

    genvar l;
    generate
        for (l = 0; l < P; l = l + 1) begin : carril
            reg signed [W-1:0] mb [0:NMAX*NMAX/P-1];
            reg signed [W-1:0] b;
            reg signed [2*W-1:0] prod;
            reg signed [ACW-1:0] acc;
            always @(posedge clk) begin
                if (wr_b && carril_w == l)
                    mb[dir_esc] <= wr_dato;
                b <= mb[dir_lee];
                prod <= a_dato * b;
                if (start)
                    acc <= 0;
                else if (v2)
                    acc <= acc + prod;
            end
            wire signed [ACW-1:0] r = (acc + MEDIO) >>> F;
            wire valido = (col0 + l) < n;
            assign res[l*W +: W] = (r > MAXP) ? MAXP[W-1:0] : (r < MINN) ? MINN[W-1:0] : r[W-1:0];
            assign sat_l[l] = valido && ((r > MAXP) || (r < MINN));
        end
    endgenerate

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            k <= 0; corre <= 0; v1 <= 0; v2 <= 0;
            u1 <= 0; u2 <= 0; u3 <= 0;
            done <= 0; C <= 0; sat <= 0;
        end else begin
            done <= 0;
            v1 <= corre;
            v2 <= v1;
            u1 <= ultimo;
            u2 <= u1;
            u3 <= u2;
            if (start) begin
                k <= 0;
                corre <= 1;
            end else if (ultimo) begin
                corre <= 0;
            end else if (corre) begin
                k <= k + 1;
            end
            if (u3) begin
                C <= res;
                sat <= |sat_l;
                done <= 1;
            end
        end
    end
endmodule
