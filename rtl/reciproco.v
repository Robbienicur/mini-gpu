module reciproco (
    input  wire        clk,
    input  wire        reset,
    input  wire        start,
    input  wire [17:0] m,
    output reg  [18:0] x,
    output reg         done
);

    localparam S_ESPERA = 2'd0;
    localparam S_PASO_A = 2'd1;
    localparam S_PASO_B = 2'd2;

    reg [1:0]  estado;
    reg        vuelta;
    reg [17:0] m_reg;
    reg [19:0] e;

    function [18:0] tabla;
        input [5:0] idx;
        begin
            case (idx)
            6'd0: tabla = 19'd260112;
            6'd1: tabla = 19'd256141;
            6'd2: tabla = 19'd252289;
            6'd3: tabla = 19'd248551;
            6'd4: tabla = 19'd244923;
            6'd5: tabla = 19'd241399;
            6'd6: tabla = 19'd237975;
            6'd7: tabla = 19'd234646;
            6'd8: tabla = 19'd231410;
            6'd9: tabla = 19'd228261;
            6'd10: tabla = 19'd225198;
            6'd11: tabla = 19'd222215;
            6'd12: tabla = 19'd219310;
            6'd13: tabla = 19'd216480;
            6'd14: tabla = 19'd213722;
            6'd15: tabla = 19'd211034;
            6'd16: tabla = 19'd208413;
            6'd17: tabla = 19'd205855;
            6'd18: tabla = 19'd203360;
            6'd19: tabla = 19'd200925;
            6'd20: tabla = 19'd198547;
            6'd21: tabla = 19'd196225;
            6'd22: tabla = 19'd193956;
            6'd23: tabla = 19'd191740;
            6'd24: tabla = 19'd189573;
            6'd25: tabla = 19'd187455;
            6'd26: tabla = 19'd185384;
            6'd27: tabla = 19'd183358;
            6'd28: tabla = 19'd181375;
            6'd29: tabla = 19'd179435;
            6'd30: tabla = 19'd177537;
            6'd31: tabla = 19'd175678;
            6'd32: tabla = 19'd173857;
            6'd33: tabla = 19'd172074;
            6'd34: tabla = 19'd170327;
            6'd35: tabla = 19'd168615;
            6'd36: tabla = 19'd166937;
            6'd37: tabla = 19'd165293;
            6'd38: tabla = 19'd163680;
            6'd39: tabla = 19'd162099;
            6'd40: tabla = 19'd160548;
            6'd41: tabla = 19'd159026;
            6'd42: tabla = 19'd157533;
            6'd43: tabla = 19'd156067;
            6'd44: tabla = 19'd154629;
            6'd45: tabla = 19'd153217;
            6'd46: tabla = 19'd151830;
            6'd47: tabla = 19'd150468;
            6'd48: tabla = 19'd149131;
            6'd49: tabla = 19'd147817;
            6'd50: tabla = 19'd146526;
            6'd51: tabla = 19'd145257;
            6'd52: tabla = 19'd144010;
            6'd53: tabla = 19'd142785;
            6'd54: tabla = 19'd141580;
            6'd55: tabla = 19'd140395;
            6'd56: tabla = 19'd139230;
            6'd57: tabla = 19'd138084;
            6'd58: tabla = 19'd136957;
            6'd59: tabla = 19'd135848;
            6'd60: tabla = 19'd134757;
            6'd61: tabla = 19'd133683;
            6'd62: tabla = 19'd132626;
            6'd63: tabla = 19'd131586;
            endcase
        end
    endfunction

    wire [36:0] mx  = m_reg * x;
    wire [38:0] xe  = x * e;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            estado <= S_ESPERA;
            vuelta <= 1'b0;
            m_reg  <= 18'd0;
            x      <= 19'd0;
            e      <= 20'd0;
            done   <= 1'b0;
        end else begin
            done <= 1'b0;

            case (estado)
                S_ESPERA: begin
                    if (start) begin
                        m_reg  <= m;
                        x      <= tabla(m[16:11]);
                        vuelta <= 1'b0;
                        estado <= S_PASO_A;
                    end
                end

                S_PASO_A: begin
                    e      <= 20'd524288 - mx[36:17];
                    estado <= S_PASO_B;
                end

                S_PASO_B: begin
                    x <= xe[36:18];
                    if (vuelta == 1'b0) begin
                        vuelta <= 1'b1;
                        estado <= S_PASO_A;
                    end else begin
                        done   <= 1'b1;
                        estado <= S_ESPERA;
                    end
                end

                default: estado <= S_ESPERA;
            endcase
        end
    end

endmodule
