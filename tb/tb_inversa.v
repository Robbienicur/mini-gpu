`timescale 1ns/1ps
module tb_inversa;
    reg         clk = 0, rst = 1, start = 0;
    reg  [7:0]  n = 3;
    reg         ld_we = 0;
    reg  [7:0]  ld_row = 0, ld_col = 0, rd_row = 0, rd_col = 0;
    reg  [31:0] ld_data = 0;
    wire        done, busy, sing, ovf, det_neg;
    wire [16:0] det_m;
    wire [15:0] det_e;
    wire [31:0] ciclos;
    wire signed [31:0] x;

    inversa #(.N(8), .W(32), .F(20), .PAR(4)) DUT (
        .clk(clk), .rst(rst), .start(start), .n(n), .done(done), .busy(busy), .sing(sing), .cycles(ciclos),
        .ovf(ovf), .det_neg(det_neg), .det_m(det_m), .det_e(det_e),
        .ld_we(ld_we), .ld_row(ld_row), .ld_col(ld_col), .ld_data(ld_data),
        .rd_row(rd_row), .rd_col(rd_col), .rd_data(x));

    always #10 clk = ~clk;

    real A [0:8];
    integer i, j;

    initial begin
        A[0] = 2; A[1] = 1; A[2] = 1;
        A[3] = 1; A[4] = 3; A[5] = 2;
        A[6] = 1; A[7] = 0; A[8] = 0;
        #20 rst = 0;
        for (i = 0; i < 8; i = i + 1)
            for (j = 0; j < 8; j = j + 1) begin
                ld_we = 1; ld_row = i; ld_col = j;
                if (i < 3 && j < 3)
                    ld_data = $rtoi(A[3*i + j] * 1048576);
                else if (i == j)
                    ld_data = 32'd1048576;
                else
                    ld_data = 0;
                #20;
            end
        ld_we = 0;
        #20 start = 1;
        #20 start = 0;
        wait (done);
        #20;
        $display("ciclos=%0d sing=%b ovf=%b det = %0s%0d * 2^%0d", ciclos, sing, ovf, det_neg ? "-" : "", det_m, $signed(det_e));
        for (i = 0; i < 3; i = i + 1) begin
            for (j = 0; j < 3; j = j + 1) begin
                rd_row = i; rd_col = j;
                #40;
                $write("%9.5f ", x / 1048576.0);
            end
            $write("\n");
        end
        $finish;
    end
endmodule
