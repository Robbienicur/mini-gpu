`timescale 1ns/1ps
module tb_multiplica;
    reg         clk = 0, reset = 1, start = 0, wr_b = 0;
    reg  [7:0]  n = 2, fila = 0, col0 = 0, wr_fila = 0, wr_col = 0;
    reg  [31:0] wr_dato = 0;
    wire [7:0]  a_col;
    reg  signed [31:0] a_dato;
    wire        done, sat;
    wire [127:0] C;

    multiplica #(.NMAX(8), .W(32), .F(20), .P(4)) DUT (
        .clk(clk), .reset(reset), .n(n), .wr_b(wr_b), .wr_fila(wr_fila), .wr_col(wr_col), .wr_dato(wr_dato),
        .start(start), .fila(fila), .col0(col0), .a_col(a_col), .a_dato(a_dato),
        .done(done), .C(C), .sat(sat));

    always #10 clk = ~clk;

    reg signed [31:0] A [0:3];
    always @(posedge clk) a_dato <= A[2*fila + a_col];

    wire signed [31:0] c0 = C[31:0], c1 = C[63:32];
    wire signed [11:0] e0 = c0 >>> 20, e1 = c1 >>> 20;

    initial begin
        $monitor("t=%0t fila=%0d done=%b  C[fila][0]=%0d C[fila][1]=%0d  sat=%b", $time, fila, done, e0, e1, sat);
        A[0] = 1 << 20; A[1] = 2 << 20; A[2] = 3 << 20; A[3] = 4 << 20;
        #20 reset = 0;
        wr_b = 1;
        wr_fila = 0; wr_col = 0; wr_dato = 5 << 20; #20;
        wr_fila = 0; wr_col = 1; wr_dato = 6 << 20; #20;
        wr_fila = 1; wr_col = 0; wr_dato = 7 << 20; #20;
        wr_fila = 1; wr_col = 1; wr_dato = 8 << 20; #20;
        wr_b = 0;
        fila = 0;
        #20 start = 1;
        #20 start = 0;
        #200 fila = 1;
        #20 start = 1;
        #20 start = 0;
        #200 $finish;
    end
endmodule
