/* 
    nlfsr_top.v
    This module is a "top" module that should be relatively independent of the actual hardware used. 
    This module can be wrapped by a board-specific module that supplies clocks etc. 
*/

`timescale 1ns / 1ps
module nlfsr_top #( parameter SHIFTREG_WIDTH = 10, 
                    parameter NUM_NLIN = 2, 
                    parameter NUM_NLIN_IDX = 2,
                    parameter NUM_TESTERS = 10,
                    parameter BRANCHES_PER_LEVEL = 5,
                    parameter UART_CPB = 8 // "Clocks per bit" - a frequency independent "baudrate"
                    )(
                    input wire clk_fast,
                    input wire clk_slow,
                    input wire reset,
                    input wire uart_rx_in,
                    output wire uart_tx_out
                );

    localparam SETTING_WIDTH = (SHIFTREG_WIDTH - 1 + (NUM_NLIN * NUM_NLIN_IDX) * $clog2(SHIFTREG_WIDTH -1));
    localparam UART_DATA_BYTES = (SETTING_WIDTH+8)/8; // By using "+8" we guarantee at least one bit that is not used by the setting - this can be a "command flag"
    localparam UART_DATA_WIDTH = UART_DATA_BYTES*8;

    // Command codes. When a command is received over UART, the FPGA will respond.
    localparam CMD_RESET = 4'h1;
    localparam CMD_READ_SETTING = 4'h2;
    localparam CMD_READ_CYCLE_COUNT = 4'h3;
    localparam CMD_READ_NUM_FOUND = 4'h4;
    localparam CMD_READ_STATUS = 4'h5;
    localparam CMD_READ_NUM_STARTED = 4'h6;

    wire [UART_DATA_WIDTH-1:0] uart_rx_data;
    reg [UART_DATA_WIDTH-1:0] uart_tx_data;

    // NLFSR distributor signals
    wire distributor_idle;
    wire distributor_running;
    wire distributor_success;
    wire [SETTING_WIDTH-1:0] distributor_setting_out;
    wire distributor_start;
    wire distributor_rd_en;

    // Fifo signals
    reg fifo_in_wr_en = 0;
    wire fifo_in_rd_en;
    wire [SETTING_WIDTH-1:0] fifo_in_din = uart_rx_data[SETTING_WIDTH-1:0];
    wire [SETTING_WIDTH-1:0] fifo_in_dout;
    wire fifo_in_empty;
    wire fifo_in_full;
    wire fifo_in_prog_empty;
    
    wire fifo_out_wr_en = distributor_rd_en;
    reg fifo_out_rd_en = 0;
    wire [SETTING_WIDTH-1:0] fifo_out_din = distributor_setting_out;
    wire [SETTING_WIDTH-1:0] fifo_out_dout;
    wire fifo_out_full;
    wire fifo_out_empty;

    // Signals for detecting problems
    reg fifo_in_overflow = 0;
    reg fifo_out_overflow = 0;

    // MISC
    wire data_is_command = uart_rx_data[UART_DATA_WIDTH-1]; // If high bit is set, this is not a polynomial but a request to do something.
    reg [UART_DATA_WIDTH-1:0] cycle_counter = 0;
    reg [UART_DATA_WIDTH-1:0] num_started = 0;
    reg [UART_DATA_WIDTH-1:0] num_found = 0;
    reg soft_reset = 0;
     
    reg sync_reset_slow = 0;
    (* ASYNC_REG = "TRUE" *) reg sync_reset_fast = 0;
    
    // Instantiate root distributor and FIFOs
    assign distributor_start = distributor_idle & ~fifo_in_empty;
    assign distributor_rd_en = ~fifo_out_full & distributor_success;
    assign fifo_in_rd_en = distributor_start; 
    
    distributor #(.NUM_LEAVES(NUM_TESTERS), .BRANCHES_PER_LEVEL(BRANCHES_PER_LEVEL), .SHIFTREG_WIDTH(SHIFTREG_WIDTH), .SETTING_WIDTH(SETTING_WIDTH), .NUM_NLIN(NUM_NLIN), .NUM_NLIN_IDX(NUM_NLIN_IDX)) 
        distributor_inst (.clk(clk_fast), .start(distributor_start), .setting_rd_en(distributor_rd_en), .setting_in(fifo_in_dout), .setting_out(distributor_setting_out), .idle(distributor_idle), .running(distributor_running), .success(distributor_success)); 
    
    localparam FIFO_DEPTH = 4096; // These don't apply to simulation.
    localparam FIFO_PROG_EMPTY = 1024;
    fifo #(.DATA_WIDTH(SETTING_WIDTH), .DEPTH(FIFO_DEPTH), .PROG_EMPTY(FIFO_PROG_EMPTY), .FWFT("TRUE")) 
        fifo_in_inst (.wrclk(clk_slow), .rdclk(clk_fast), .reset_w(sync_reset_slow), .reset_r(sync_reset_fast), .fifo_din(fifo_in_din), .fifo_dout(fifo_in_dout), 
        .fifo_wr_en(fifo_in_wr_en), .fifo_rd_en(fifo_in_rd_en), .fifo_empty(fifo_in_empty), .fifo_full(fifo_in_full), .fifo_prog_empty(fifo_in_prog_empty));
    
    fifo #(.DATA_WIDTH(SETTING_WIDTH), .DEPTH(FIFO_DEPTH), .PROG_EMPTY(FIFO_PROG_EMPTY), .FWFT("TRUE"))
        fifo_out_inst (.wrclk(clk_fast), .rdclk(clk_slow), .reset_w(sync_reset_fast), .reset_r(sync_reset_slow), .fifo_din(fifo_out_din), .fifo_dout(fifo_out_dout), 
        .fifo_wr_en(fifo_out_wr_en), .fifo_rd_en(fifo_out_rd_en), .fifo_empty(fifo_out_empty), .fifo_full(fifo_out_full), .fifo_prog_empty());


    always @(posedge clk_fast) begin
        if (sync_reset_fast) begin
            num_started <= 0;
            num_found <= 0;
            fifo_out_overflow <= 0;
        end else begin 
            if (distributor_start)
                num_started <= num_started + 1;
            if (distributor_rd_en)
                num_found <= num_found + 1;
            if (fifo_out_full & fifo_out_wr_en)
                fifo_out_overflow <= 1;
        end
    end

    always @(posedge clk_slow) begin
        if (sync_reset_slow) begin
            fifo_in_overflow <= 0;
            cycle_counter <= 0;
        end else begin
            cycle_counter <= cycle_counter + 1;
            if (fifo_in_full & fifo_in_wr_en)
                fifo_in_overflow <= 1;
        end
    end

    /* ******** Clock Domain Crossings ******** */
    // Create sync reset signals
    (* ASYNC_REG = "TRUE" *) reg sync_reset_slow_FFSYNC;
    (* ASYNC_REG = "TRUE" *) reg sync_reset_fast_FFSYNC;
    always @(posedge clk_slow) begin
        {sync_reset_slow, sync_reset_slow_FFSYNC} <= {sync_reset_slow_FFSYNC, reset | soft_reset}; // Source is either soft reset or reset input signal
    end
    always @(posedge clk_fast) begin
        {sync_reset_fast, sync_reset_fast_FFSYNC} <= {sync_reset_fast_FFSYNC, sync_reset_slow}; // Source is slow domain reset signal
    end

    // Sync various signals from fast domain to slow domain
    (* ASYNC_REG = "TRUE" *) reg fifo_in_empty_FFSYNC;
    (* ASYNC_REG = "TRUE" *) reg fifo_in_empty_slow;
    (* ASYNC_REG = "TRUE" *) reg fifo_in_prog_empty_FFSYNC;
    (* ASYNC_REG = "TRUE" *) reg fifo_in_prog_empty_slow;
    (* ASYNC_REG = "TRUE" *) reg distributor_running_FFSYNC;
    (* ASYNC_REG = "TRUE" *) reg distributor_running_slow;
    (* ASYNC_REG = "TRUE" *) reg fifo_out_overflow_FFSYNC;
    (* ASYNC_REG = "TRUE" *) reg fifo_out_overflow_slow;
    (* ASYNC_REG = "TRUE" *) reg [UART_DATA_WIDTH-1:0] num_found_FFSYNC; // Multi bit CDC with two stage FF is not reccommended, but these are non-critical and fairly slow-changing
    (* ASYNC_REG = "TRUE" *) reg [UART_DATA_WIDTH-1:0] num_found_slow;
    (* ASYNC_REG = "TRUE" *) reg [UART_DATA_WIDTH-1:0] num_started_FFSYNC;
    (* ASYNC_REG = "TRUE" *) reg [UART_DATA_WIDTH-1:0] num_started_slow;

    always @(posedge clk_slow) begin
        {fifo_in_empty_slow, fifo_in_empty_FFSYNC} <= {fifo_in_empty_FFSYNC, fifo_in_empty};
        {distributor_running_slow, distributor_running_FFSYNC} <= {distributor_running_FFSYNC, distributor_running};
        {fifo_in_prog_empty_slow, fifo_in_prog_empty_FFSYNC} <= {fifo_in_prog_empty_FFSYNC, fifo_in_prog_empty};
        {fifo_out_overflow_slow, fifo_out_overflow_FFSYNC} <= {fifo_out_overflow_FFSYNC, fifo_out_overflow};
        {num_found_slow, num_found_FFSYNC} <= {num_found_FFSYNC, num_found};
        {num_started_slow, num_started_FFSYNC} <= {num_started_FFSYNC, num_started};
    end

    wire [5:0] status = {fifo_out_overflow_slow, fifo_in_overflow, fifo_out_empty, distributor_running_slow, fifo_in_empty_slow, fifo_in_prog_empty_slow};

    /* ******** UART sender, receiver, and control logic for responding to UART messages ******** */
    wire uart_rx_done;
    wire uart_tx_done;
    reg uart_rx_start = 1;
    reg uart_tx_start = 0;

    // UART receiver module, for receiving commands and data. 
    receiver #(.N_BYTES(UART_DATA_BYTES), .CLKS_PER_BIT(UART_CPB)) uart_receiver (.clk(clk_slow), .reset(sync_reset_slow), .start(uart_rx_start), .rx_pin(uart_rx_in), .done(uart_rx_done), .rx_data(uart_rx_data));
    // UART sender module, for responding to commands.
    sender #(.N_BYTES(UART_DATA_BYTES), .CLKS_PER_BIT(UART_CPB)) uart_sender (.clk(clk_slow), .reset(sync_reset_slow), .start(uart_tx_start), .tx_data(uart_tx_data), .tx_pin(uart_tx_out), .done(uart_tx_done));

    always @(posedge clk_slow) begin
        fifo_in_wr_en <= 0;
        fifo_out_rd_en <= 0;
        uart_tx_start <= 0;
        uart_rx_start <= 0;
        soft_reset <= 0;
        
        if (sync_reset_slow) begin
            uart_rx_start <= 1;
        end else begin
            if (uart_rx_done & (!uart_rx_start)) begin
                uart_rx_start <= 1;
                if (data_is_command) begin // We received a command. Handle it
                    case (uart_rx_data[3:0])
                        CMD_RESET: begin
                            soft_reset <= 1;
                        end
                        CMD_READ_CYCLE_COUNT: begin
                            uart_tx_start <= 1;
                            uart_tx_data <= cycle_counter;
                        end
                        CMD_READ_NUM_FOUND: begin
                            uart_tx_start <= 1;
                            uart_tx_data <= num_found_slow;
                        end
                        CMD_READ_SETTING: begin
                            uart_tx_start <= 1;
                            uart_tx_data <= fifo_out_dout;
                            fifo_out_rd_en <= 1;
                        end
                        CMD_READ_STATUS: begin
                            uart_tx_start <= 1; 
                            uart_tx_data <= status;
                        end
                        CMD_READ_NUM_STARTED: begin
                            uart_tx_start <= 1;
                            uart_tx_data <= num_started_slow;
                        end
                    endcase
                end else begin
                    // We just received a polynomial that needs to be tested. Write it to the fifo.
                   fifo_in_wr_en <= 1; 
                end
            end
        end
    end
endmodule