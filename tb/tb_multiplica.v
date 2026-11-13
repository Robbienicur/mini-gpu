`timescale 1ns/1ps
module tb_multiplica;
    reg          clk = 0, reset = 1, start = 0;
    reg  [287:0] A, B;
    wire [287:0] C;
    wire         done, sat;

    multiplica_seq DUT (.clk(clk), .reset(reset), .start(start), .A(A), .B(B), .C(C), .done(done), .sat(sat));

    always #10 clk = ~clk;

    wire signed [17:0] C00 = C[17:0],  C01 = C[35:18];
    wire signed [17:0] C10 = C[89:72], C11 = C[107:90];

    initial begin
        $monitor("t=%0t done=%b  C00=%0d C01=%0d C10=%0d C11=%0d  sat=%b", $time, done, C00, C01, C10, C11, sat);
        A = 0; B = 0;
        A[17:0] = 18'd1024;  A[35:18] = 18'd2048;  A[89:72] = 18'd3072;  A[107:90] = 18'd4096;
        B[17:0] = 18'd5120;  B[35:18] = 18'd6144;  B[89:72] = 18'd7168;  B[107:90] = 18'd8192;
        #20 reset = 0;
        #20 start = 1;
        #20 start = 0;
        #1500;
        $finish;
    end
endmodule
