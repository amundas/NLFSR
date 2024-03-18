// Wraps the top module with board-specific stuff
module genesys_top_wrapper (
    input wire sysclk_p,
	input wire sysclk_n,
    input wire cpu_resetn,
    input wire uart_tx_in,
    output wire [7:0] led,
    output wire uart_rx_out,
    output wire FAN_PWM
);
    `include "build_settings.vh"
    
    assign led = 8'h00;
    wire clk_fast;
    wire clk_slow;
    wire top_uart_rx;
    wire top_uart_tx;
    wire reset;
    
    assign uart_rx_out = top_uart_tx;
    assign top_uart_rx = uart_tx_in;

    // Instantiate the top module
    localparam integer UART_CPB = (`REF_CLK_FREQ * `CLK_MULT /(`UART_BAUD * `SLOW_CLK_DIV));

    nlfsr_top #(.SHIFTREG_WIDTH(`SHIFTREG_WIDTH), .NUM_NLIN(`NUM_NLIN), .NUM_NLIN_IDX(`NUM_NLIN_IDX), .NUM_TESTERS(`NUM_TESTERS), .BRANCHES_PER_LEVEL(`BRANCHES_PER_LEVEL), .UART_CPB(UART_CPB))
        top_inst (.clk_fast(clk_fast), .clk_slow(clk_slow), .reset(reset), .uart_rx_in(top_uart_rx), .uart_tx_out(top_uart_tx));

    // Generate clocks based on the 200MHz differential clock on the board
    wire mmcm_locked;
    wire clk_ref;
    IBUFDS clkin1_ibufgds (.O(clk_ref), .I(sysclk_p), .IB(sysclk_n));
    mmcm_wrapper #(.CLK_IN_PERIOD_NS(1e9/`REF_CLK_FREQ), .CLK_MULT(`CLK_MULT), .CLK0_DIV(`FAST_CLK_DIV), .CLK1_DIV(`SLOW_CLK_DIV)) 
        mmcm_inst (.reset(1'b0), .clk_ref(clk_ref), .clk_out0(clk_fast), .clk_out1(clk_slow), .locked(mmcm_locked));

    assign reset = ~cpu_resetn & ~mmcm_locked;

    assign FAN_PWM = 1'b1;
    
    // Note: By using the xadc wizard in vivado, temperature limits for when to turn the heatsink fan on or off can be set. 
    /*
    wire user_temp_alarm;
    wire alarm;
    assign FAN_PWM = user_temp_alarm;
    xadc_wiz_0 xadc_tempalarm (
        .reset_in(reset), 
        .alarm_out(alarm), 
        .user_temp_alarm_out(user_temp_alarm),
        .vp_in(1'b0),
        .vn_in(1'b0),
        .busy_out(),
        .channel_out(),
        .eoc_out(), 
        .eos_out(),
        .ot_out()
    );
    */

endmodule
