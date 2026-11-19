module inversa (
    input  wire         clk,
    input  wire         reset,
    input  wire         start,
    input  wire [287:0] A,
    output reg  [287:0] X,
    output reg  [31:0]  det_out,
    output reg          sing,
    output reg          ovf,
    output reg          done
);

    localparam S_ESPERA   = 4'd0;
    localparam S_COF_A    = 4'd1;
    localparam S_COF_B    = 4'd2;
    localparam S_COF_C    = 4'd3;
    localparam S_DET_A    = 4'd4;
    localparam S_DET_B    = 4'd5;
    localparam S_CERO     = 4'd6;
    localparam S_NORMA    = 4'd7;
    localparam S_RECIP    = 4'd8;
    localparam S_SAL_A    = 4'd9;
    localparam S_SAL_B    = 4'd10;

    reg [3:0] estado;
    reg [3:0] n;
    reg [6:0] k;

    function signed [17:0] elem;
        input [287:0] M;
        input [1:0]   r;
        input [1:0]   c;
        begin
            elem = M[18*(4*r + c) +: 18];
        end
    endfunction

    function [1:0] queda;
        input [1:0] q;
        input [1:0] t;
        begin
            queda = (t < q) ? t : t + 2'd1;
        end
    endfunction

    wire [1:0] ci = n[3:2];
    wire [1:0] cj = n[1:0];

    wire [1:0] r0 = queda(ci, 2'd0), r1 = queda(ci, 2'd1), r2 = queda(ci, 2'd2);
    wire [1:0] c0 = queda(cj, 2'd0), c1 = queda(cj, 2'd1), c2 = queda(cj, 2'd2);

    wire signed [17:0] m00 = elem(A, r0, c0), m01 = elem(A, r0, c1), m02 = elem(A, r0, c2);
    wire signed [17:0] m10 = elem(A, r1, c0), m11 = elem(A, r1, c1), m12 = elem(A, r1, c2);
    wire signed [17:0] m20 = elem(A, r2, c0), m21 = elem(A, r2, c1), m22 = elem(A, r2, c2);

    reg signed [36:0] d0, d1, d2;
    reg signed [55:0] p0, p1, p2;
    wire signed [55:0] det3 = p0 - p1 + p2;

    reg signed [55:0] cof [0:15];

    reg  signed [73:0] D;
    reg  [1:0]         col;
    reg  signed [73:0] pd;

    reg  [73:0] D_abs;
    reg         rec_start;
    wire [18:0] rec_x;
    wire        rec_done;
    reg  [18:0] x;

    reciproco REC (
        .clk(clk),
        .reset(reset),
        .start(rec_start),
        .m(D_abs[73:56]),
        .x(rec_x),
        .done(rec_done)
    );

    wire [1:0] sr = n[3:2];
    wire [1:0] sc = n[1:0];
    wire signed [55:0] cof_sal = cof[{sc, sr}];
    wire signed [75:0] P0 = cof_sal * $signed({1'b0, x});
    reg  signed [79:0] P;
    wire signed [7:0]  sh = 8'sd71 - $signed({1'b0, k});

    reg signed [79:0] q;
    always @(*) begin
        if (sh > 0)
            q = P >>> sh;
        else
            q = P <<< (-sh);
    end

    wire signed [73:0] D_red = D >>> 30;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            estado    <= S_ESPERA;
            n         <= 4'd0;
            k         <= 7'd0;
            col       <= 2'd0;
            d0        <= 37'sd0;
            d1        <= 37'sd0;
            d2        <= 37'sd0;
            p0        <= 56'sd0;
            p1        <= 56'sd0;
            p2        <= 56'sd0;
            pd        <= 74'sd0;
            P         <= 80'sd0;
            D         <= 74'sd0;
            D_abs     <= 74'd0;
            x         <= 19'd0;
            rec_start <= 1'b0;
            X         <= 288'd0;
            det_out   <= 32'd0;
            sing      <= 1'b0;
            ovf       <= 1'b0;
            done      <= 1'b0;
        end else begin
            done      <= 1'b0;
            rec_start <= 1'b0;

            case (estado)
                S_ESPERA: begin
                    if (start) begin
                        n      <= 4'd0;
                        sing   <= 1'b0;
                        ovf    <= 1'b0;
                        estado <= S_COF_A;
                    end
                end

                S_COF_A: begin
                    d0     <= m11 * m22 - m12 * m21;
                    d1     <= m10 * m22 - m12 * m20;
                    d2     <= m10 * m21 - m11 * m20;
                    estado <= S_COF_B;
                end

                S_COF_B: begin
                    p0     <= m00 * d0;
                    p1     <= m01 * d1;
                    p2     <= m02 * d2;
                    estado <= S_COF_C;
                end

                S_COF_C: begin
                    if (ci[0] ^ cj[0])
                        cof[n] <= -det3;
                    else
                        cof[n] <= det3;
                    if (n == 4'd15) begin
                        D      <= 74'sd0;
                        col    <= 2'd0;
                        estado <= S_DET_A;
                    end else begin
                        n      <= n + 4'd1;
                        estado <= S_COF_A;
                    end
                end

                S_DET_A: begin
                    pd     <= elem(A, 2'd0, col) * cof[{2'd0, col}];
                    estado <= S_DET_B;
                end

                S_DET_B: begin
                    D <= D + pd;
                    if (col == 2'd3) begin
                        estado <= S_CERO;
                    end else begin
                        col    <= col + 2'd1;
                        estado <= S_DET_A;
                    end
                end

                S_CERO: begin
                    if (D == 74'sd0) begin
                        sing    <= 1'b1;
                        X       <= 288'd0;
                        det_out <= 32'd0;
                        done    <= 1'b1;
                        estado  <= S_ESPERA;
                    end else begin
                        D_abs  <= D[73] ? -D : D;
                        k      <= 7'd0;
                        estado <= S_NORMA;
                    end
                end

                S_NORMA: begin
                    if (D_abs[73] == 1'b0) begin
                        D_abs <= D_abs << 1;
                        k     <= k + 7'd1;
                    end else begin
                        rec_start <= 1'b1;
                        estado    <= S_RECIP;
                    end
                end

                S_RECIP: begin
                    if (rec_done) begin
                        x      <= rec_x;
                        n      <= 4'd0;
                        estado <= S_SAL_A;
                    end
                end

                S_SAL_A: begin
                    P      <= D[73] ? -P0 : P0;
                    estado <= S_SAL_B;
                end

                S_SAL_B: begin
                    if (q > 80'sd131071) begin
                        X[18*n +: 18] <= 18'h1FFFF;
                        ovf <= 1'b1;
                    end else if (q < -80'sd131072) begin
                        X[18*n +: 18] <= 18'h20000;
                        ovf <= 1'b1;
                    end else begin
                        X[18*n +: 18] <= q[17:0];
                    end

                    if (n == 4'd15) begin
                        if (D_red > 74'sd2147483647)
                            det_out <= 32'h7FFFFFFF;
                        else if (D_red < -74'sd2147483648)
                            det_out <= 32'h80000000;
                        else
                            det_out <= D_red[31:0];
                        done   <= 1'b1;
                        estado <= S_ESPERA;
                    end else begin
                        n      <= n + 4'd1;
                        estado <= S_SAL_A;
                    end
                end

                default: estado <= S_ESPERA;
            endcase
        end
    end

endmodule
