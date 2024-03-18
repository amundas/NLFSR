
`ifdef __ICARUS__
`define __SIMULATING__
`elsif VERILATOR
`define __SIMULATING__
`endif

module fifo #(parameter DATA_WIDTH = 40, parameter DEPTH = 4096, parameter PROG_EMPTY = 1024, parameter FWFT = "FALSE")
                 (input wire wrclk,
                  input wire rdclk,
                  input wire reset_w, // reset sync to write clock
                  input wire reset_r, // reset sync to read clock
                  input wire [DATA_WIDTH-1:0] fifo_din,
                  output wire [DATA_WIDTH-1:0]fifo_dout,
                  input wire fifo_wr_en,
                  input wire fifo_rd_en,
                  output wire fifo_empty,
                  output wire fifo_full,
                  output wire fifo_prog_empty);


    `ifdef __SIMULATING__
        // Simulating XPMs is a bit tricky, so we use another implementation for simulation
        wire arempty;
        assign fifo_prog_empty = arempty | fifo_empty; // not as good as prog_empty, but earlier than the empty signal
        async_fifo #(.DSIZE(DATA_WIDTH), .ASIZE(4), .FALLTHROUGH(FWFT)) fifo_inst (
            .wclk(wrclk),
            .wrst_n(~reset_w),
            .winc(fifo_wr_en),
            .wdata(fifo_din),
            .wfull(fifo_full),
            .awfull(),
            .rclk(rdclk),
            .rrst_n(~reset_r),
            .rinc(fifo_rd_en),
            .rdata(fifo_dout),
            .rempty(fifo_empty),
            .arempty(arempty)
        );
    `else 

    xpm_fifo_async #(
    .CASCADE_HEIGHT(0),
    .CDC_SYNC_STAGES(2),
    .DOUT_RESET_VALUE("0"),
    .ECC_MODE("no_ecc"),
    .FIFO_MEMORY_TYPE("auto"),
    .FIFO_READ_LATENCY(0),
    .FIFO_WRITE_DEPTH(DEPTH),
    .FULL_RESET_VALUE(0),
    .PROG_EMPTY_THRESH(PROG_EMPTY),
    .PROG_FULL_THRESH(2048), 
    .RD_DATA_COUNT_WIDTH(1),
    .READ_DATA_WIDTH(DATA_WIDTH),
    .READ_MODE("fwft"),
    .RELATED_CLOCKS(0),
    .SIM_ASSERT_CHK(0),
    .USE_ADV_FEATURES("0200"), // Only enable "prog_empty"
    .WAKEUP_TIME(0),
    .WRITE_DATA_WIDTH(DATA_WIDTH),
    .WR_DATA_COUNT_WIDTH(1)
    )
    xpm_fifo_async_inst (
        .almost_empty(),
        .almost_full(), 
        .data_valid(), 
        .dbiterr(),
        .dout(fifo_dout),
        .empty(fifo_empty), 
        .full(fifo_full),
        .overflow(),
        .prog_empty(fifo_prog_empty),
        .prog_full(), 
        .rd_data_count(),
        .rd_rst_busy(),
        .sbiterr(),
        .underflow(),
        .wr_ack(),
        .wr_data_count(),
        .wr_rst_busy(),
        .din(fifo_din),
        .injectdbiterr(1'b0),
        .injectsbiterr(1'b0), 
        .rd_clk(rdclk),
        .rd_en(fifo_rd_en),
        .rst(reset_w),
        .sleep(1'b0),
        .wr_clk(wrclk),
        .wr_en(fifo_wr_en) 
    );
    `endif
endmodule