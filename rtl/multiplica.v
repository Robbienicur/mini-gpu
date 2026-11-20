module multiplica (
    input  wire         clk,
    input  wire         reset,
    input  wire         start,
    input  wire [287:0] A,
    input  wire [287:0] B,
    output reg  [287:0] C,
    output reg          done,
    output reg          sat
);

    localparam S_ESPERA = 2'd0;
    localparam S_MAC    = 2'd1;
    localparam S_GUARDA = 2'd2;

    reg [1:0] estado;
    reg [1:0] i;
    reg [1:0] k;

    wire signed [17:0] a  = A[18*(4*i + k) +: 18];
    wire signed [17:0] b0 = B[18*(4*k + 0) +: 18];
    wire signed [17:0] b1 = B[18*(4*k + 1) +: 18];
    wire signed [17:0] b2 = B[18*(4*k + 2) +: 18];
    wire signed [17:0] b3 = B[18*(4*k + 3) +: 18];

    reg signed [39:0] acc0, acc1, acc2, acc3;

    function [18:0] ajusta;
        input signed [39:0] x;
        reg   signed [39:0] y;
        begin
            y = x >>> 10;
            if (y > 40'sd131071)
                ajusta = {1'b1, 18'h1FFFF};
            else if (y < -40'sd131072)
                ajusta = {1'b1, 18'h20000};
            else
                ajusta = {1'b0, y[17:0]};
        end
    endfunction

    reg [18:0] r0, r1, r2, r3;
    always @(*) begin
        r0 = ajusta(acc0);
        r1 = ajusta(acc1);
        r2 = ajusta(acc2);
        r3 = ajusta(acc3);
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            estado <= S_ESPERA;
            i      <= 2'd0;
            k      <= 2'd0;
            acc0   <= 40'sd0;
            acc1   <= 40'sd0;
            acc2   <= 40'sd0;
            acc3   <= 40'sd0;
            C      <= 288'd0;
            done   <= 1'b0;
            sat    <= 1'b0;
        end else begin
            done <= 1'b0;

            case (estado)
                S_ESPERA: begin
                    if (start) begin
                        i      <= 2'd0;
                        k      <= 2'd0;
                        sat    <= 1'b0;
                        estado <= S_MAC;
                    end
                end

                S_MAC: begin
                    acc0 <= (k == 2'd0 ? 40'sd0 : acc0) + a * b0;
                    acc1 <= (k == 2'd0 ? 40'sd0 : acc1) + a * b1;
                    acc2 <= (k == 2'd0 ? 40'sd0 : acc2) + a * b2;
                    acc3 <= (k == 2'd0 ? 40'sd0 : acc3) + a * b3;
                    if (k == 2'd3)
                        estado <= S_GUARDA;
                    else
                        k <= k + 2'd1;
                end

                S_GUARDA: begin
                    C[18*(4*i + 0) +: 18] <= r0[17:0];
                    C[18*(4*i + 1) +: 18] <= r1[17:0];
                    C[18*(4*i + 2) +: 18] <= r2[17:0];
                    C[18*(4*i + 3) +: 18] <= r3[17:0];
                    if (r0[18] | r1[18] | r2[18] | r3[18])
                        sat <= 1'b1;
                    k <= 2'd0;
                    if (i == 2'd3) begin
                        done   <= 1'b1;
                        estado <= S_ESPERA;
                    end else begin
                        i      <= i + 2'd1;
                        estado <= S_MAC;
                    end
                end

                default: estado <= S_ESPERA;
            endcase
        end
    end

endmodule
