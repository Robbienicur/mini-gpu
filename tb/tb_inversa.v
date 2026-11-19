`timescale 1ns/1ps
module tb_inversa;
    reg          clk = 0, reset = 1, start = 0;
    reg  [287:0] A;
    wire [287:0] X;
    wire [31:0]  det;
    wire         sing, ovf, done;

    inversa DUT (.clk(clk), .reset(reset), .start(start), .A(A), .X(X), .det_out(det),
                 .sing(sing), .ovf(ovf), .done(done));

    always #10 clk = ~clk;

    wire signed [17:0] X00 = X[17:0],  X01 = X[35:18];
    wire signed [17:0] X10 = X[89:72], X11 = X[107:90];
    wire signed [31:0] D = det;

    initial begin
        $monitor("t=%0t done=%b det=%0d  X00=%0d X01=%0d X10=%0d X11=%0d  sing=%b ovf=%b", $time, done,
                 D, X00, X01, X10, X11, sing, ovf);
        A = 0;
        A[17:0] = 18'd4096;  A[35:18] = 18'd7168;  A[89:72] = 18'd2048;  A[107:90] = 18'd6144;
        A[197:180] = 18'd1024;  A[287:270] = 18'd1024;
        #20 reset = 0;
        #20 start = 1;
        #20 start = 0;
        #3000;
        A[35:18] = 18'd2048; A[89:72] = 18'd2048; A[17:0] = 18'd1024; A[107:90] = 18'd4096;
        #20 start = 1;
        #20 start = 0;
        #3000;
        $finish;
    end
endmodule
