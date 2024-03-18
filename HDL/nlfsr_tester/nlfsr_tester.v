/*
    This module takes in a setting representing an NLFSR feedback function and tests it for period length.
    This specific version does:
    * Use two shift registers, one going forward and one going backward.
    * The nonlinear parts of the feedback function are evaluated using indexation. The setting represents indexes that should be used.

    The format for setting_in is (where n = SHIFTREG_WIDTH):
        - The first n-1 bits control the inclusion of linear terms x_1 to x_{n-1}. (x_0 is hardwired to be part of the feedback function)
        - Then there are NUM_NLIN * NUM_NLIN_IDX * $clog2(SHIFTREG_WIDTH - 1) bits representing the nonlinear terms.
            - a chunk of $clog2(SHIFTREG_WIDTH - 1) bits represent the position of a tap starting at 1. There are NUM_NLIN_IDX such taps per nonlinear term
        - Example: SHIFTREG_WIDTH = 10, NUM_NLIN = 1, NUM_NLIN_IDX = 2 and setting_in = 0b0110_0010_000001001
            - the first n-1 bits gives us the linear terms x_1 + x_4
            - the nonlinear part consists of two taps, with indexes (1 + 2) and (1 + 6) meaning it is x_3 * x_7
            - the whole feedback function is x_0 + x_1 + x_4 + (x_3 * x_ 7)
*/

`timescale 1ns / 1ps
module nlfsr_tester #(  parameter SHIFTREG_WIDTH = 10,
                        parameter NUM_NLIN = 1, 
                        parameter NUM_NLIN_IDX = 2,
                        parameter SETTING_WIDTH = SHIFTREG_WIDTH - 1 + (NUM_NLIN * NUM_NLIN_IDX) * $clog2(SHIFTREG_WIDTH - 1)
                        ) (
                        input wire clk,
                        input wire start,
                        input wire setting_rd_en,
                        input wire [SETTING_WIDTH-1:0] setting_in,
                        output wire [SETTING_WIDTH-1:0] setting_out,
                        output wire idle,
                        output reg success = 0
                        );

    // Sensible init values can be taken from the parts that are guaranteed to be in the full sequence: 0001 -> 1000 or 1110 -> 1111 -> 0111
    localparam INIT_VAL_FW = {1'b1, {(SHIFTREG_WIDTH-1){1'b0}}};
    localparam INIT_VAL_BW = {{(SHIFTREG_WIDTH-1){1'b0}}, 1'b1};
    localparam IDX_WIDTH = $clog2(SHIFTREG_WIDTH-1);

    reg [SHIFTREG_WIDTH-1:0] sr_fw = INIT_VAL_FW; // The shift register going "forwards"
    reg [SHIFTREG_WIDTH-1:0] sr_bw = INIT_VAL_BW; // The reciprocal shift register going "backwards"
    reg [SETTING_WIDTH-1:0] setting = 0;
    reg [SHIFTREG_WIDTH-2:0] counter = 0; // We only need n-1 bits. This is because we go backwards and forwards
    reg running = 0;

    assign idle = ~running & ~success;
    assign setting_out = setting;
    
    wire [SHIFTREG_WIDTH-1:0] lin_fw = {setting[0 +:SHIFTREG_WIDTH-1], 1'b1}; // x_0 is hardcoded 
    wire [SHIFTREG_WIDTH-1:0] lin_bw = {1'b1, lin_fw[SHIFTREG_WIDTH-1:1]}; // linear part of reciprocal/backward feedback function
    wire [SHIFTREG_WIDTH-2:0] sr_fw_upper = sr_fw[SHIFTREG_WIDTH-1:1]; // Just a helper

    // Get the linear part of the feedback functions
    wire fb_fw_lin =  (^(lin_fw & sr_fw));
    wire fb_bw_lin =  (^(lin_bw & sr_bw));

    // Get the nonlinear part of the feedback functions
    reg fb_fw_nlin;
    reg fb_bw_nlin;
    reg [IDX_WIDTH-1:0] idx;
    reg tmp_fw;
    reg tmp_bw;
    integer i, j;
    always @(*) begin
        fb_fw_nlin = 0;
        fb_bw_nlin = 0;
        for (i = 0; i < NUM_NLIN; i = i + 1) begin
            tmp_fw = 1'b1;
            tmp_bw = 1'b1;
            for (j = 0; j < NUM_NLIN_IDX; j = j + 1) begin
                idx = setting[SHIFTREG_WIDTH-1 + IDX_WIDTH*(i*NUM_NLIN_IDX+j) +:IDX_WIDTH];
                tmp_fw = tmp_fw & sr_fw_upper[idx];
                tmp_bw = tmp_bw & sr_bw[idx];
            end
            fb_fw_nlin = fb_fw_nlin ^ tmp_fw;
            fb_bw_nlin = fb_bw_nlin ^ tmp_bw;
        end
    end

    wire fb_fw = fb_fw_lin ^ fb_fw_nlin;
    wire fb_bw = fb_bw_lin ^ fb_bw_nlin;

    reg fw_thrownbit = 0;
    wire [SHIFTREG_WIDTH-1:0] prev_fw = {sr_fw[SHIFTREG_WIDTH-2:0], fw_thrownbit};

    // Fail or success conditions
    wire counter_done = &counter; // We are done at ..11111
    wire shiftregs_equal = (sr_fw == sr_bw); // Two equality checks, one detects odd and one detects even cycles
    wire missed_equal = (prev_fw == sr_bw); 

    always @(posedge clk) begin
        if (counter_done & shiftregs_equal) begin
            success <= 1;
        end else if (start | setting_rd_en) begin
            success <= 0;
        end  
    end
    always @(posedge clk) begin
        if (start) begin
            sr_fw <= INIT_VAL_FW; 
            sr_bw <= INIT_VAL_BW;
            setting <= setting_in;
            running <= 1;
            counter <= 0;
            fw_thrownbit <= 0;
        end else if (running) begin
            sr_fw <= {fb_fw, sr_fw[SHIFTREG_WIDTH-1:1]};
            sr_bw <= {sr_bw[SHIFTREG_WIDTH-2:0], fb_bw};
            fw_thrownbit <= sr_fw[0];
            running <= ~(shiftregs_equal | missed_equal | counter_done);
            counter <= counter + 1;
        end
    end
endmodule