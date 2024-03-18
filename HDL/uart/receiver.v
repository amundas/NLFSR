
module receiver #(parameter N_BYTES = 16, parameter CLKS_PER_BIT = 35)
                 (input wire clk,
                  input wire reset,
                  input wire start,
                  input wire rx_pin,
                  output reg done,
                  output wire [N_BYTES*8-1:0] rx_data);
    
    localparam STATE_IDLE = 2'b00;
    localparam STATE_BUSY = 2'b01;
    localparam M          = $clog2(N_BYTES);
    
    reg [1:0] state;
    reg [N_BYTES*8-1:0] data_sr; // Shiftreg
    reg [M:0] counter;
    wire [7:0] rx_byte;
    wire rx_dv;
    assign rx_data = data_sr;
    
    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) uart_rx  (.i_Clock(clk), .i_Rx_Serial(rx_pin), .o_Rx_DV(rx_dv), .o_Rx_Byte(rx_byte));
    
    always @(posedge clk) begin

        if (reset) begin
            state   <= STATE_IDLE;
            counter <= 0;
            done    <= 0;
            data_sr <= 0;
            end else begin
            case (state)
                STATE_IDLE: begin
                    if (start) begin
                        data_sr <= 0;
                        state   <= STATE_BUSY;
                        done    <= 0;
                    end
                end
                STATE_BUSY: begin
                    if (rx_dv) begin
                        data_sr[7:0]           <= rx_byte;
                        data_sr[N_BYTES*8-1:8] <= data_sr[(N_BYTES-1)*8-1:0];
                        counter                <= counter + 1;
                        if (counter == N_BYTES -1) begin
                            state   <= STATE_IDLE;
                            counter <= 0;
                            done    <= 1;
                        end
                    end
                end
                default: begin
                    
                end
        
            endcase
        end
    end
endmodule
