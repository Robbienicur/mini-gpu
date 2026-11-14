module inversa_lu (
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

    localparam S_ESPERA = 4'd0;
    localparam S_CARGA  = 4'd1;
    localparam S_LU_PIV = 4'd2;
    localparam S_LU_FAC = 4'd3;
    localparam S_LU_ELM = 4'd4;
    localparam S_DET    = 4'd5;
    localparam S_FWD_A  = 4'd6;
    localparam S_FWD_B  = 4'd7;
    localparam S_BWD_A  = 4'd8;
    localparam S_BWD_B  = 4'd9;
    localparam S_GUARDA = 4'd10;

    reg [3:0] estado;
    reg signed [31:0] M [0:15];
    reg signed [31:0] y [0:3];
    reg signed [31:0] xv [0:3];
    reg signed [31:0] piv, fac;
    reg signed [63:0] acc, det_acc;
    reg [1:0] k, i, j, col;
    integer t;

    wire signed [63:0] num_fac = $signed(M[4*i + k]) <<< 10;
    wire signed [63:0] prod_lu = $signed(fac) * $signed(M[4*k + j]);
    wire signed [63:0] num_bwd = acc <<< 10;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            estado  <= S_ESPERA;
            X       <= 288'd0;
            det_out <= 32'd0;
            sing    <= 1'b0;
            ovf     <= 1'b0;
            done    <= 1'b0;
            k       <= 2'd0;
            i       <= 2'd0;
            j       <= 2'd0;
            col     <= 2'd0;
            piv     <= 32'sd0;
            fac     <= 32'sd0;
            acc     <= 64'sd0;
            det_acc <= 64'sd1024;
        end else begin
            done <= 1'b0;

            case (estado)
                S_ESPERA: begin
                    if (start) begin
                        sing   <= 1'b0;
                        ovf    <= 1'b0;
                        estado <= S_CARGA;
                    end
                end

                S_CARGA: begin
                    for (t = 0; t < 16; t = t + 1)
                        M[t] <= {{14{A[18*t + 17]}}, A[18*t +: 18]};
                    k      <= 2'd0;
                    estado <= S_LU_PIV;
                end

                S_LU_PIV: begin
                    piv <= M[4*k + k];
                    if (M[4*k + k] == 32'sd0) begin
                        sing    <= 1'b1;
                        X       <= 288'd0;
                        det_out <= 32'd0;
                        done    <= 1'b1;
                        estado  <= S_ESPERA;
                    end else if (k == 2'd3) begin
                        det_acc <= 64'sd1024;
                        i       <= 2'd0;
                        estado  <= S_DET;
                    end else begin
                        i      <= k + 2'd1;
                        estado <= S_LU_FAC;
                    end
                end

                S_LU_FAC: begin
                    fac        <= num_fac / piv;
                    M[4*i + k] <= num_fac / piv;
                    j          <= k + 2'd1;
                    estado     <= S_LU_ELM;
                end

                S_LU_ELM: begin
                    M[4*i + j] <= M[4*i + j] - (prod_lu >>> 10);
                    if (j == 2'd3) begin
                        if (i == 2'd3) begin
                            k      <= k + 2'd1;
                            estado <= S_LU_PIV;
                        end else begin
                            i      <= i + 2'd1;
                            estado <= S_LU_FAC;
                        end
                    end else begin
                        j <= j + 2'd1;
                    end
                end

                S_DET: begin
                    det_acc <= (det_acc * $signed(M[4*i + i])) >>> 10;
                    if (i == 2'd3) begin
                        col    <= 2'd0;
                        i      <= 2'd0;
                        estado <= S_FWD_A;
                    end else begin
                        i <= i + 2'd1;
                    end
                end

                S_FWD_A: begin
                    acc <= (i == col) ? 64'sd1024 : 64'sd0;
                    j   <= 2'd0;
                    if (i == 2'd0) begin
                        y[0] <= (col == 2'd0) ? 32'sd1024 : 32'sd0;
                        i    <= 2'd1;
                    end else begin
                        estado <= S_FWD_B;
                    end
                end

                S_FWD_B: begin
                    if (j < i) begin
                        acc <= acc - (($signed(M[4*i + j]) * $signed(y[j])) >>> 10);
                        j   <= j + 2'd1;
                    end else begin
                        y[i] <= acc[31:0];
                        if (i == 2'd3) begin
                            i      <= 2'd3;
                            estado <= S_BWD_A;
                        end else begin
                            i      <= i + 2'd1;
                            estado <= S_FWD_A;
                        end
                    end
                end

                S_BWD_A: begin
                    acc <= y[i];
                    if (i == 2'd3) begin
                        xv[3]  <= ($signed(y[3]) <<< 10) / $signed(M[15]);
                        i      <= 2'd2;
                    end else begin
                        j      <= i + 2'd1;
                        estado <= S_BWD_B;
                    end
                end

                S_BWD_B: begin
                    acc <= acc - (($signed(M[4*i + j]) * $signed(xv[j])) >>> 10);
                    if (j == 2'd3) begin
                        xv[i] <= ((acc - (($signed(M[4*i + j]) * $signed(xv[j])) >>> 10)) <<< 10) / $signed(M[4*i + i]);
                        if (i == 2'd0) begin
                            i      <= 2'd0;
                            estado <= S_GUARDA;
                        end else begin
                            i      <= i - 2'd1;
                            estado <= S_BWD_A;
                        end
                    end else begin
                        j <= j + 2'd1;
                    end
                end

                S_GUARDA: begin
                    if (xv[i] > 32'sd131071) begin
                        X[18*(4*i + col) +: 18] <= 18'h1FFFF;
                        ovf <= 1'b1;
                    end else if (xv[i] < -32'sd131072) begin
                        X[18*(4*i + col) +: 18] <= 18'h20000;
                        ovf <= 1'b1;
                    end else begin
                        X[18*(4*i + col) +: 18] <= xv[i][17:0];
                    end

                    if (i == 2'd3) begin
                        if (col == 2'd3) begin
                            det_out <= det_acc[31:0];
                            done    <= 1'b1;
                            estado  <= S_ESPERA;
                        end else begin
                            col    <= col + 2'd1;
                            i      <= 2'd0;
                            estado <= S_FWD_A;
                        end
                    end else begin
                        i <= i + 2'd1;
                    end
                end

                default: estado <= S_ESPERA;
            endcase
        end
    end

endmodule
