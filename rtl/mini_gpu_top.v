module mini_gpu_top #(
    parameter BAUD = 9600,
    parameter NG   = 64
)(
    input  wire       CLOCK_50,
    input  wire       RESET_N,
    input  wire       UART_RX,
    output wire       UART_TX,
    output wire [6:0] HEX0,
    output wire [6:0] HEX1,
    output wire [6:0] HEX2,
    output wire [6:0] HEX3,
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

    reg [287:0] A, B;
    reg [2:0]   op;
    reg         inicio;

    wire [287:0] C_sr, C_mul, X_inv;
    wire         sat_sr, sat_mul, done_mul;
    wire [31:0]  det_inv;
    wire         sing_inv, ovf_inv, done_inv;

    suma_resta SR (
        .A(A), .B(B), .resta(op == 3'd2),
        .C(C_sr), .sat(sat_sr)
    );

    multiplica MUL (
        .clk(clk), .reset(reset), .start(inicio && op == 3'd3),
        .A(A), .B(B),
        .C(C_mul), .done(done_mul), .sat(sat_mul)
    );

    inversa INV (
        .clk(clk), .reset(reset), .start(inicio && op == 3'd4),
        .A(A),
        .X(X_inv), .det_out(det_inv), .sing(sing_inv), .ovf(ovf_inv), .done(done_inv)
    );

    localparam LOGN = 2 * $clog2(NG);
    localparam N    = NG * NG;

    reg                c_we;
    reg  [LOGN-1:0]    c_addr;
    reg  [31:0]        c_b;
    reg                c_start;
    wire               c_done, c_conv, c_nc, c_stag, c_err, c_busy;
    wire [15:0]        c_iters;
    wire [31:0]        c_ciclos;
    wire signed [31:0] c_x;

    cg_estencil #(.NG(NG), .WV(32), .FV(24)) CG (
        .clk(clk), .rst(reset),
        .ld_b_we(c_we), .ld_b_addr(c_addr), .ld_b_data(c_b),
        .start(c_start), .maxit(16'd300), .tolsh(7'd28),
        .done(c_done), .busy(c_busy), .conv(c_conv), .nc(c_nc), .stag(c_stag), .err(c_err),
        .iters(c_iters), .cycles(c_ciclos),
        .x_addr(c_addr), .x_data(c_x)
    );

    reg  [7:0] t_arriba, t_abajo, t_izq, t_der;
    reg  [1:0] tn;
    wire [LOGN/2-1:0] fila = c_addr[LOGN-1:LOGN/2];
    wire [LOGN/2-1:0] col  = c_addr[LOGN/2-1:0];
    wire [31:0] b_borde = ((fila == 0)      ? {8'd0, t_arriba, 16'd0} : 32'd0)
                        + ((fila == NG - 1) ? {8'd0, t_abajo,  16'd0} : 32'd0)
                        + ((col  == 0)      ? {8'd0, t_izq,    16'd0} : 32'd0)
                        + ((col  == NG - 1) ? {8'd0, t_der,    16'd0} : 32'd0);
    wire [31:0] c_xr   = c_x + 32'd32768;
    wire [7:0]  grados = c_xr[31] ? 8'd0 : (c_xr[30:24] != 7'd0) ? 8'd255 : c_xr[23:16];

    localparam S_ESPERA_OP   = 4'd0;
    localparam S_RECIBE_A    = 4'd1;
    localparam S_RECIBE_B    = 4'd2;
    localparam S_CALCULA     = 4'd3;
    localparam S_ESPERA_FIN  = 4'd4;
    localparam S_PREPARA     = 4'd5;
    localparam S_ENVIA       = 4'd6;
    localparam S_ENVIA_PAUSA = 4'd7;
    localparam S_C_TEMP      = 4'd8;
    localparam S_C_CARGA     = 4'd9;
    localparam S_C_SIG       = 4'd10;
    localparam S_C_CORRE     = 4'd11;
    localparam S_C_LEE       = 4'd12;
    localparam S_C_ESPERA    = 4'd13;
    localparam S_C_MANDA     = 4'd14;
    localparam S_C_PAUSA     = 4'd15;

    reg [3:0]   estado;
    reg [3:0]   num;
    reg [1:0]   byte_n;
    reg [7:0]   b0, b1;
    reg [31:0]  ciclos;
    reg [287:0] R;
    reg [31:0]  det;
    reg         sing, sat;
    reg [455:0] paquete;
    reg [5:0]   enviados;
    integer     t;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            estado   <= S_ESPERA_OP;
            op       <= 3'd0;
            num      <= 4'd0;
            byte_n   <= 2'd0;
            b0       <= 8'd0;
            b1       <= 8'd0;
            A        <= 288'd0;
            B        <= 288'd0;
            inicio   <= 1'b0;
            ciclos   <= 32'd0;
            R        <= 288'd0;
            det      <= 32'd0;
            sing     <= 1'b0;
            sat      <= 1'b0;
            paquete  <= 456'd0;
            enviados <= 6'd0;
            tx_start <= 1'b0;
            tx_data  <= 8'd0;
            c_we     <= 1'b0;
            c_addr   <= 0;
            c_b      <= 32'd0;
            c_start  <= 1'b0;
            tn       <= 2'd0;
            t_arriba <= 8'd0;
            t_abajo  <= 8'd0;
            t_izq    <= 8'd0;
            t_der    <= 8'd0;
        end else begin
            tx_start <= 1'b0;
            inicio   <= 1'b0;
            c_we     <= 1'b0;
            c_start  <= 1'b0;

            case (estado)
                S_ESPERA_OP: begin
                    if (rx_done && rx_data >= 8'd1 && rx_data <= 8'd4) begin
                        op     <= rx_data[2:0];
                        num    <= 4'd0;
                        byte_n <= 2'd0;
                        estado <= S_RECIBE_A;
                    end else if (rx_done && rx_data == 8'd5) begin
                        op     <= 3'd5;
                        tn     <= 2'd0;
                        estado <= S_C_TEMP;
                    end
                end

                S_C_TEMP: begin
                    if (rx_done) begin
                        if (tn == 2'd0) t_arriba <= rx_data;
                        if (tn == 2'd1) t_abajo  <= rx_data;
                        if (tn == 2'd2) t_izq    <= rx_data;
                        if (tn == 2'd3) t_der    <= rx_data;
                        tn <= tn + 2'd1;
                        if (tn == 2'd3) begin
                            c_addr <= 0;
                            estado <= S_C_CARGA;
                        end
                    end
                end

                S_C_CARGA: begin
                    c_we   <= 1'b1;
                    c_b    <= b_borde;
                    estado <= S_C_SIG;
                end

                S_C_SIG: begin
                    if (c_addr == N - 1) begin
                        c_start <= 1'b1;
                        estado  <= S_C_CORRE;
                    end else begin
                        c_addr <= c_addr + 1'b1;
                        estado <= S_C_CARGA;
                    end
                end

                S_C_CORRE: begin
                    if (c_done) begin
                        ciclos <= c_ciclos;
                        sing   <= ~c_conv;
                        sat    <= c_nc | c_stag | c_err;
                        c_addr <= 0;
                        estado <= S_C_LEE;
                    end
                end

                S_C_LEE: begin
                    estado <= S_C_ESPERA;
                end

                S_C_ESPERA: begin
                    estado <= S_C_MANDA;
                end

                S_C_MANDA: begin
                    if (!tx_busy) begin
                        tx_data  <= grados;
                        tx_start <= 1'b1;
                        estado   <= S_C_PAUSA;
                    end
                end

                S_C_PAUSA: begin
                    if (c_addr == N - 1) begin
                        paquete[55:0] <= {ciclos, 4'd0, c_err, c_stag, c_nc, c_conv, c_iters};
                        enviados      <= 6'd50;
                        estado        <= S_ENVIA;
                    end else begin
                        c_addr <= c_addr + 1'b1;
                        estado <= S_C_LEE;
                    end
                end

                S_RECIBE_A: begin
                    if (rx_done) begin
                        if (byte_n == 2'd0) begin
                            b0     <= rx_data;
                            byte_n <= 2'd1;
                        end else if (byte_n == 2'd1) begin
                            b1     <= rx_data;
                            byte_n <= 2'd2;
                        end else begin
                            A[18*num +: 18] <= {rx_data[1:0], b1, b0};
                            byte_n <= 2'd0;
                            if (num == 4'd15) begin
                                num <= 4'd0;
                                if (op == 3'd4)
                                    estado <= S_CALCULA;
                                else
                                    estado <= S_RECIBE_B;
                            end else begin
                                num <= num + 4'd1;
                            end
                        end
                    end
                end

                S_RECIBE_B: begin
                    if (rx_done) begin
                        if (byte_n == 2'd0) begin
                            b0     <= rx_data;
                            byte_n <= 2'd1;
                        end else if (byte_n == 2'd1) begin
                            b1     <= rx_data;
                            byte_n <= 2'd2;
                        end else begin
                            B[18*num +: 18] <= {rx_data[1:0], b1, b0};
                            byte_n <= 2'd0;
                            if (num == 4'd15) begin
                                num    <= 4'd0;
                                estado <= S_CALCULA;
                            end else begin
                                num <= num + 4'd1;
                            end
                        end
                    end
                end

                S_CALCULA: begin
                    inicio <= 1'b1;
                    ciclos <= 32'd0;
                    estado <= S_ESPERA_FIN;
                end

                S_ESPERA_FIN: begin
                    ciclos <= ciclos + 32'd1;
                    if (op == 3'd1 || op == 3'd2) begin
                        R      <= C_sr;
                        det    <= 32'd0;
                        sing   <= 1'b0;
                        sat    <= sat_sr;
                        estado <= S_PREPARA;
                    end else if (op == 3'd3 && done_mul) begin
                        R      <= C_mul;
                        det    <= 32'd0;
                        sing   <= 1'b0;
                        sat    <= sat_mul;
                        estado <= S_PREPARA;
                    end else if (op == 3'd4 && done_inv) begin
                        R      <= X_inv;
                        det    <= det_inv;
                        sing   <= sing_inv;
                        sat    <= ovf_inv;
                        estado <= S_PREPARA;
                    end
                end

                S_PREPARA: begin
                    for (t = 0; t < 16; t = t + 1)
                        paquete[24*t +: 24] <= {{6{R[18*t + 17]}}, R[18*t +: 18]};
                    paquete[415:384] <= det;
                    paquete[423:416] <= {6'd0, sat, sing};
                    paquete[455:424] <= ciclos;
                    enviados <= 6'd0;
                    estado   <= S_ENVIA;
                end

                S_ENVIA: begin
                    if (!tx_busy) begin
                        tx_data  <= paquete[7:0];
                        tx_start <= 1'b1;
                        paquete  <= paquete >> 8;
                        enviados <= enviados + 6'd1;
                        estado   <= S_ENVIA_PAUSA;
                    end
                end

                S_ENVIA_PAUSA: begin
                    if (enviados == 6'd57)
                        estado <= S_ESPERA_OP;
                    else
                        estado <= S_ENVIA;
                end

                default: estado <= S_ESPERA_OP;
            endcase
        end
    end

    wire [15:0] mostrar = (op == 3'd5) ? c_iters : ciclos[15:0];

    Decodificador D0 (.hex(mostrar[3:0]),   .HEX0(HEX0));
    Decodificador D1 (.hex(mostrar[7:4]),   .HEX0(HEX1));
    Decodificador D2 (.hex(mostrar[11:8]),  .HEX0(HEX2));
    Decodificador D3 (.hex(mostrar[15:12]), .HEX0(HEX3));

    assign LEDR[0]   = sing;
    assign LEDR[1]   = sat;
    assign LEDR[4:2] = op;
    assign LEDR[8:5] = 4'd0;
    assign LEDR[9]   = (estado != S_ESPERA_OP);

endmodule
