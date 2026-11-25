module mini_gpu_top #(
    parameter BAUD = 115200,
    parameter NMAX = 128,
    parameter W    = 32,
    parameter F    = 20,
    parameter P    = 16
)(
    input  wire       CLOCK_50,
    input  wire       RESET_N,
    input  wire       UART_RX,
    output wire       UART_TX,
    output wire [6:0] HEX0,
    output wire [6:0] HEX1,
    output wire [6:0] HEX2,
    output wire [6:0] HEX3,
    output wire [6:0] HEX4,
    output wire [6:0] HEX5,
    output wire [9:0] LEDR
);

    wire reset = ~RESET_N;

    reg [1:0] div = 2'd0;
    always @(posedge CLOCK_50)
        div <= div + 2'd1;
    wire clk = div[1];

    wire [7:0] rx_data;
    wire       rx_done;
    reg  [7:0] tx_data;
    reg        tx_start;
    wire       tx_busy;

    uart_rx #(
        .CLK_FREQ(12500000),
        .BAUD_RATE(BAUD)
    ) RX0 (
        .clk(clk),
        .reset(reset),
        .rx(UART_RX),
        .data_out(rx_data),
        .data_valid(rx_done)
    );

    uart_tx #(
        .CLK_FREQ(12500000),
        .BAUD_RATE(BAUD)
    ) TX0 (
        .clk(clk),
        .reset(reset),
        .tx_start(tx_start),
        .data_in(tx_data),
        .tx(UART_TX),
        .busy(tx_busy)
    );

    localparam [W-1:0] UNO = 1 << F;

    reg  [1:0]   op;
    reg  [7:0]   n;
    reg  [7:0]   fila, col;
    reg          inv_rst, inv_start, mul_start;
    reg          ld_we;
    reg  [7:0]   ld_fila, ld_col;
    reg  [W-1:0] ld_dato;
    reg          wb;

    wire         inv_done, inv_busy, inv_sing, inv_ovf, inv_dneg;
    wire [16:0]  inv_dm;
    wire [15:0]  inv_de;
    wire [31:0]  inv_ciclos;
    wire [W-1:0] inv_dato;

    wire         mul_done, mul_sat;
    wire [7:0]   mul_col;
    wire [P*W-1:0] mul_C;

    inversa #(.N(NMAX), .W(W), .F(F), .PAR(P)) INV (
        .clk(clk), .rst(reset | inv_rst), .start(inv_start), .n(n),
        .done(inv_done), .busy(inv_busy), .sing(inv_sing), .cycles(inv_ciclos), .ovf(inv_ovf),
        .det_neg(inv_dneg), .det_m(inv_dm), .det_e(inv_de),
        .ld_we(ld_we), .ld_row(ld_fila), .ld_col(ld_col), .ld_data(ld_dato),
        .rd_row(fila), .rd_col(op == 2'd1 ? mul_col : col), .rd_data(inv_dato)
    );

    multiplica #(.NMAX(NMAX), .W(W), .F(F), .P(P)) MUL (
        .clk(clk), .reset(reset), .n(n),
        .wr_b(wb), .wr_fila(ld_fila), .wr_col(ld_col), .wr_dato(ld_dato),
        .start(mul_start), .fila(fila), .col0(col),
        .a_col(mul_col), .a_dato(inv_dato),
        .done(mul_done), .C(mul_C), .sat(mul_sat)
    );

    localparam S_OP       = 4'd0;
    localparam S_N        = 4'd1;
    localparam S_DATO     = 4'd2;
    localparam S_RELLENA  = 4'd3;
    localparam S_INV      = 4'd4;
    localparam S_INV_FIN  = 4'd5;
    localparam S_LEE      = 4'd6;
    localparam S_LEE2     = 4'd7;
    localparam S_INV_SIG  = 4'd8;
    localparam S_M_CALC   = 4'd9;
    localparam S_M_ESPERA = 4'd10;
    localparam S_M_MANDA  = 4'd11;
    localparam S_M_SIG    = 4'd12;
    localparam S_COLA     = 4'd13;
    localparam S_TX       = 4'd14;
    localparam S_TX_PAUSA = 4'd15;

    reg [3:0]  estado, regreso;
    reg [1:0]  byte_n;
    reg [23:0] pal;
    reg        cual;
    reg [31:0] ciclos;
    reg        sing, sat, dneg;
    reg [16:0] dm;
    reg [15:0] de;
    reg [79:0] salida;
    reg [3:0]  faltan;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            estado    <= S_OP;
            regreso   <= S_OP;
            op        <= 2'd0;
            n         <= 8'd0;
            fila      <= 8'd0;
            col       <= 8'd0;
            byte_n    <= 2'd0;
            pal       <= 24'd0;
            cual      <= 1'b0;
            inv_rst   <= 1'b0;
            inv_start <= 1'b0;
            mul_start <= 1'b0;
            ld_we     <= 1'b0;
            ld_fila   <= 8'd0;
            ld_col    <= 8'd0;
            ld_dato   <= 0;
            wb        <= 1'b0;
            ciclos    <= 32'd0;
            sing      <= 1'b0;
            sat       <= 1'b0;
            dneg      <= 1'b0;
            dm        <= 17'd0;
            de        <= 16'd0;
            salida    <= 80'd0;
            faltan    <= 4'd0;
            tx_start  <= 1'b0;
            tx_data   <= 8'd0;
        end else begin
            tx_start  <= 1'b0;
            inv_rst   <= 1'b0;
            inv_start <= 1'b0;
            mul_start <= 1'b0;
            ld_we     <= 1'b0;
            wb        <= 1'b0;

            case (estado)
                S_OP: begin
                    if (rx_done && (rx_data == 8'd1 || rx_data == 8'd2)) begin
                        op      <= rx_data[1:0];
                        inv_rst <= 1'b1;
                        estado  <= S_N;
                    end
                end

                S_N: begin
                    if (rx_done) begin
                        n      <= (rx_data == 8'd0 || rx_data > NMAX) ? NMAX : rx_data;
                        fila   <= 8'd0;
                        col    <= 8'd0;
                        byte_n <= 2'd0;
                        cual   <= 1'b0;
                        ciclos <= 32'd0;
                        sing   <= 1'b0;
                        sat    <= 1'b0;
                        dneg   <= 1'b0;
                        dm     <= 17'd0;
                        de     <= 16'd0;
                        estado <= S_DATO;
                    end
                end

                S_DATO: begin
                    if (rx_done) begin
                        if (byte_n != 2'd3) begin
                            pal    <= {rx_data, pal[23:8]};
                            byte_n <= byte_n + 2'd1;
                        end else begin
                            byte_n  <= 2'd0;
                            ld_fila <= fila;
                            ld_col  <= col;
                            ld_dato <= {rx_data, pal};
                            if (cual == 1'b0)
                                ld_we <= 1'b1;
                            else
                                wb <= 1'b1;
                            if (col == n - 1) begin
                                col <= 8'd0;
                                if (fila == n - 1) begin
                                    fila <= 8'd0;
                                    if (op == 2'd1 && cual == 1'b0)
                                        cual <= 1'b1;
                                    else if (op == 2'd1)
                                        estado <= S_M_CALC;
                                    else
                                        estado <= S_RELLENA;
                                end else begin
                                    fila <= fila + 8'd1;
                                end
                            end else begin
                                col <= col + 8'd1;
                            end
                        end
                    end
                end

                S_RELLENA: begin
                    ld_we   <= (fila >= n) || (col >= n);
                    ld_fila <= fila;
                    ld_col  <= col;
                    ld_dato <= (fila == col) ? UNO : 0;
                    if (col == NMAX - 1) begin
                        col <= 8'd0;
                        if (fila == NMAX - 1) begin
                            fila   <= 8'd0;
                            estado <= S_INV;
                        end else begin
                            fila <= fila + 8'd1;
                        end
                    end else begin
                        col <= col + 8'd1;
                    end
                end

                S_INV: begin
                    inv_start <= 1'b1;
                    estado    <= S_INV_FIN;
                end

                S_INV_FIN: begin
                    if (inv_done) begin
                        ciclos <= inv_ciclos;
                        sing   <= inv_sing;
                        sat    <= inv_ovf;
                        dneg   <= inv_sing ? 1'b0 : inv_dneg;
                        dm     <= inv_sing ? 17'd0 : inv_dm;
                        de     <= inv_sing ? 16'd0 : inv_de;
                        estado <= S_LEE;
                    end
                end

                S_LEE: begin
                    estado <= S_LEE2;
                end

                S_LEE2: begin
                    salida[W-1:0] <= inv_dato;
                    faltan        <= 4'd4;
                    regreso       <= S_INV_SIG;
                    estado        <= S_TX;
                end

                S_INV_SIG: begin
                    estado <= S_LEE;
                    if (col == n - 1) begin
                        col <= 8'd0;
                        if (fila == n - 1)
                            estado <= S_COLA;
                        else
                            fila <= fila + 8'd1;
                    end else begin
                        col <= col + 8'd1;
                    end
                end

                S_M_CALC: begin
                    mul_start <= 1'b1;
                    ciclos    <= ciclos + 32'd1;
                    estado    <= S_M_ESPERA;
                end

                S_M_ESPERA: begin
                    ciclos <= ciclos + 32'd1;
                    if (mul_done) begin
                        sat    <= sat | mul_sat;
                        estado <= S_M_MANDA;
                    end
                end

                S_M_MANDA: begin
                    salida[W-1:0] <= mul_C[col[3:0]*W +: W];
                    faltan        <= 4'd4;
                    regreso       <= S_M_SIG;
                    estado        <= S_TX;
                end

                S_M_SIG: begin
                    if (col == n - 1) begin
                        col <= 8'd0;
                        if (fila == n - 1) begin
                            estado <= S_COLA;
                        end else begin
                            fila   <= fila + 8'd1;
                            estado <= S_M_CALC;
                        end
                    end else begin
                        col    <= col + 8'd1;
                        estado <= (col[3:0] == P - 1) ? S_M_CALC : S_M_MANDA;
                    end
                end

                S_COLA: begin
                    salida  <= {ciclos, de, 7'd0, dm, 5'd0, dneg, sat, sing};
                    faltan  <= 4'd10;
                    regreso <= S_OP;
                    estado  <= S_TX;
                end

                S_TX: begin
                    if (!tx_busy) begin
                        tx_data  <= salida[7:0];
                        tx_start <= 1'b1;
                        salida   <= salida >> 8;
                        faltan   <= faltan - 4'd1;
                        estado   <= S_TX_PAUSA;
                    end
                end

                S_TX_PAUSA: begin
                    estado <= (faltan == 4'd0) ? regreso : S_TX;
                end

                default: estado <= S_OP;
            endcase
        end
    end

    Decodificador D0 (.hex(ciclos[3:0]),   .HEX0(HEX0));
    Decodificador D1 (.hex(ciclos[7:4]),   .HEX0(HEX1));
    Decodificador D2 (.hex(ciclos[11:8]),  .HEX0(HEX2));
    Decodificador D3 (.hex(ciclos[15:12]), .HEX0(HEX3));
    Decodificador D4 (.hex(ciclos[19:16]), .HEX0(HEX4));
    Decodificador D5 (.hex(ciclos[23:20]), .HEX0(HEX5));

    assign LEDR[0]   = sing;
    assign LEDR[1]   = sat;
    assign LEDR[2]   = dneg;
    assign LEDR[3]   = (op == 2'd1);
    assign LEDR[4]   = (op == 2'd2);
    assign LEDR[8:5] = 4'd0;
    assign LEDR[9]   = (estado != S_OP);

endmodule
