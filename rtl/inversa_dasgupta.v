module inversa_dasgupta (
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
    localparam S_BUSCA  = 4'd2;
    localparam S_SWAP   = 4'd3;
    localparam S_PIV    = 4'd4;
    localparam S_FILA   = 4'd5;
    localparam S_ELIM   = 4'd6;
    localparam S_COL    = 4'd7;
    localparam S_GUARDA = 4'd8;

    reg [3:0] estado;
    reg signed [31:0] M [0:15];
    reg signed [31:0] col_k [0:3];
    reg [1:0] perm [0:3];
    reg det_neg;
    reg [1:0] k, i, j, piv_r;
    reg signed [31:0] max_v, inv_p;
    reg signed [63:0] det_acc;
    integer t;

    wire signed [31:0] cur_v = M[4*i + k];
    wire signed [31:0] abs_v = cur_v[31] ? -cur_v : cur_v;
    wire signed [63:0] p_fila = $signed(M[4*k + j]) * $signed(inv_p);
    wire signed [63:0] p_elim = $signed(col_k[i]) * $signed(M[4*k + j]);
    wire signed [63:0] p_col  = $signed(col_k[i]) * $signed(inv_p);

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
            piv_r   <= 2'd0;
            det_neg <= 1'b0;
            max_v   <= 32'sd0;
            inv_p   <= 32'sd0;
            det_acc <= 64'sd1024;
        end else begin
            done <= 1'b0;

            case (estado)
                S_ESPERA: begin
                    if (start) begin
                        sing    <= 1'b0;
                        ovf     <= 1'b0;
                        det_neg <= 1'b0;
                        det_acc <= 64'sd1024;
                        estado  <= S_CARGA;
                    end
                end

                S_CARGA: begin
                    for (t = 0; t < 16; t = t + 1)
                        M[t] <= {{14{A[18*t + 17]}}, A[18*t +: 18]};
                    perm[0] <= 2'd0;
                    perm[1] <= 2'd1;
                    perm[2] <= 2'd2;
                    perm[3] <= 2'd3;
                    k       <= 2'd0;
                    i       <= 2'd0;
                    piv_r   <= 2'd0;
                    max_v   <= 32'sd0;
                    estado  <= S_BUSCA;
                end

                S_BUSCA: begin
                    if (i == k || abs_v > max_v) begin
                        max_v <= abs_v;
                        piv_r <= i;
                    end
                    if (i == 2'd3) begin
                        j      <= 2'd0;
                        estado <= S_SWAP;
                    end else begin
                        i <= i + 2'd1;
                    end
                end

                S_SWAP: begin
                    if (piv_r != k) begin
                        M[4*k + j]     <= M[4*piv_r + j];
                        M[4*piv_r + j] <= M[4*k + j];
                        if (j == 2'd3) begin
                            perm[k]     <= perm[piv_r];
                            perm[piv_r] <= perm[k];
                            det_neg     <= ~det_neg;
                            estado      <= S_PIV;
                        end else begin
                            j <= j + 2'd1;
                        end
                    end else begin
                        estado <= S_PIV;
                    end
                end

                S_PIV: begin
                    if (M[4*k + k] == 32'sd0) begin
                        sing    <= 1'b1;
                        X       <= 288'd0;
                        det_out <= 32'd0;
                        done    <= 1'b1;
                        estado  <= S_ESPERA;
                    end else begin
                        inv_p      <= 64'sd1048576 / $signed(M[4*k + k]);
                        det_acc    <= (det_acc * $signed(M[4*k + k])) >>> 10;
                        col_k[0]   <= M[0 + k];
                        col_k[1]   <= M[4 + k];
                        col_k[2]   <= M[8 + k];
                        col_k[3]   <= M[12 + k];
                        M[4*k + k] <= 64'sd1048576 / $signed(M[4*k + k]);
                        j          <= 2'd0;
                        estado     <= S_FILA;
                    end
                end

                S_FILA: begin
                    if (j != k)
                        M[4*k + j] <= p_fila >>> 10;
                    if (j == 2'd3) begin
                        i      <= 2'd0;
                        j      <= 2'd0;
                        estado <= S_ELIM;
                    end else begin
                        j <= j + 2'd1;
                    end
                end

                S_ELIM: begin
                    if (i != k && j != k)
                        M[4*i + j] <= M[4*i + j] - (p_elim >>> 10);
                    if (j == 2'd3) begin
                        j <= 2'd0;
                        if (i == 2'd3) begin
                            i      <= 2'd0;
                            estado <= S_COL;
                        end else begin
                            i <= i + 2'd1;
                        end
                    end else begin
                        j <= j + 2'd1;
                    end
                end

                S_COL: begin
                    if (i != k)
                        M[4*i + k] <= -(p_col >>> 10);
                    if (i == 2'd3) begin
                        if (k == 2'd3) begin
                            i      <= 2'd0;
                            j      <= 2'd0;
                            estado <= S_GUARDA;
                        end else begin
                            k      <= k + 2'd1;
                            i      <= k + 2'd1;
                            piv_r  <= k + 2'd1;
                            max_v  <= 32'sd0;
                            estado <= S_BUSCA;
                        end
                    end else begin
                        i <= i + 2'd1;
                    end
                end

                S_GUARDA: begin
                    if (M[4*i + j] > 32'sd131071) begin
                        X[18*(4*i + perm[j]) +: 18] <= 18'h1FFFF;
                        ovf <= 1'b1;
                    end else if (M[4*i + j] < -32'sd131072) begin
                        X[18*(4*i + perm[j]) +: 18] <= 18'h20000;
                        ovf <= 1'b1;
                    end else begin
                        X[18*(4*i + perm[j]) +: 18] <= M[4*i + j][17:0];
                    end

                    if (j == 2'd3) begin
                        j <= 2'd0;
                        if (i == 2'd3) begin
                            det_out <= det_neg ? -det_acc[31:0] : det_acc[31:0];
                            done    <= 1'b1;
                            estado  <= S_ESPERA;
                        end else begin
                            i <= i + 2'd1;
                        end
                    end else begin
                        j <= j + 2'd1;
                    end
                end

                default: estado <= S_ESPERA;
            endcase
        end
    end

endmodule
