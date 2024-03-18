/*
    CLKS_PER_BIT decides baudrate
    frequency of clock divided by baudrate should be CLK_PER_BIT
*/

module sender #(parameter N_BYTES = 16, parameter CLKS_PER_BIT = 35)  (
        input wire clk,
        input wire reset,
        input wire start,
        input wire [N_BYTES*8-1:0] tx_data, // All the data to send
        output wire tx_pin,
        output reg done);

    localparam STATE_IDLE = 2'b00;
    localparam STATE_PREPARE_BYTE = 2'b01;
    localparam STATE_SEND_BYTE = 2'b10;

    localparam M = $clog2(N_BYTES);

    reg [1:0] state = STATE_IDLE;
    reg [N_BYTES*8-1:0] data_sr; // Shiftreg
    reg [M:0] counter = 0;
    reg tx_start = 0;
    wire tx_done;
    wire [7:0] tx_byte = data_sr[N_BYTES*8-1:(N_BYTES-1)*8];
    wire tx_active;

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) uart_tx (.i_Clock(clk), .i_Tx_DV(tx_start), .i_Tx_Byte(tx_byte), .o_Tx_Active(tx_active), .o_Tx_Serial(tx_pin), .o_Tx_Done(tx_done));

    always @(posedge clk) begin
        if (reset) begin
            state <= STATE_IDLE;
            counter <= 0;
            tx_start <= 0;
            done <= 0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    if (start) begin
                        data_sr <= tx_data;
                        state <= STATE_PREPARE_BYTE;
                        done <= 0;
                        counter <= 0;
                    end
                end
                STATE_PREPARE_BYTE: begin
                    tx_start <= 1;
                    state <= STATE_SEND_BYTE;
                end
                STATE_SEND_BYTE: begin
                    tx_start <= 0;
                    if (tx_done) begin
                        data_sr[N_BYTES*8-1:8] <= data_sr[(N_BYTES-1)*8-1:0];
                        counter <= counter + 1;
                        if (counter == N_BYTES -1) begin
                            state <= STATE_IDLE;
                            done <= 1;
                        end else begin
                            state <= STATE_PREPARE_BYTE;
                        end
                    end
                end
            endcase
        end
    end
endmodule
