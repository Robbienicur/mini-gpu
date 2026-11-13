module multiplica_seq (
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
    localparam S_CALC   = 2'd1;

    reg [1:0] estado;
    reg [1:0] i, j, k;
    reg signed [39:0] acc;

    wire signed [17:0] a = A[18*(4*i + k) +: 18];
    wire signed [17:0] b = B[18*(4*k + j) +: 18];
    wire signed [39:0] suma = (k == 2'd0 ? 40'sd0 : acc) + a * b;
    wire signed [39:0] q = suma >>> 10;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            estado <= S_ESPERA;
            i      <= 2'd0;
            j      <= 2'd0;
            k      <= 2'd0;
            acc    <= 40'sd0;
            C      <= 288'd0;
            done   <= 1'b0;
            sat    <= 1'b0;
        end else begin
            done <= 1'b0;

            case (estado)
                S_ESPERA: begin
                    if (start) begin
                        i      <= 2'd0;
                        j      <= 2'd0;
                        k      <= 2'd0;
                        acc    <= 40'sd0;
                        sat    <= 1'b0;
                        estado <= S_CALC;
                    end
                end

                S_CALC: begin
                    if (k == 2'd3) begin
                        if (q > 40'sd131071) begin
                            C[18*(4*i + j) +: 18] <= 18'h1FFFF;
                            sat <= 1'b1;
                        end else if (q < -40'sd131072) begin
                            C[18*(4*i + j) +: 18] <= 18'h20000;
                            sat <= 1'b1;
                        end else begin
                            C[18*(4*i + j) +: 18] <= q[17:0];
                        end
                        acc <= 40'sd0;
                        k   <= 2'd0;
                        if (j == 2'd3) begin
                            j <= 2'd0;
                            if (i == 2'd3) begin
                                done   <= 1'b1;
                                estado <= S_ESPERA;
                            end else begin
                                i <= i + 2'd1;
                            end
                        end else begin
                            j <= j + 2'd1;
                        end
                    end else begin
                        acc <= suma;
                        k   <= k + 2'd1;
                    end
                end

                default: estado <= S_ESPERA;
            endcase
        end
    end

endmodule
