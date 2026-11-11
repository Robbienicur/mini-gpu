`timescale 1ns/1ps
module tb_suma_resta;
    reg  [287:0] A, B;
    reg          resta;
    wire [287:0] C;
    wire         sat;

    suma_resta DUT (.A(A), .B(B), .resta(resta), .C(C), .sat(sat));

    wire signed [17:0] C00 = C[17:0];
    wire signed [17:0] C01 = C[35:18];

    initial begin
        $monitor("t=%0t resta=%b  C[0][0]=%0d  C[0][1]=%0d  sat=%b", $time, resta, C00, C01, sat);
        A = 0; B = 0;
        A[17:0] = 18'd3072;   A[35:18] = 18'd1024;
        B[17:0] = 18'd512;    B[35:18] = 18'd2048;
        resta = 0; #10;
        resta = 1; #10;
        A[17:0] = 18'd102400; B[17:0] = 18'd102400;
        resta = 0; #10;
        $finish;
    end
endmodule
