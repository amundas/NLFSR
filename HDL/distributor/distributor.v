/*
    Distributor module.
    This module is a branch point in a recursively instantiated tree. 
    This module will pass data and signals up and down the tree.
*/
`timescale 1ns / 1ps
module distributor  #(  parameter SHIFTREG_WIDTH = 10, 
                        parameter NUM_NLIN = 2, 
                        parameter NUM_NLIN_IDX = 2,
                        parameter SETTING_WIDTH = SHIFTREG_WIDTH-1 + (NUM_NLIN * NUM_NLIN_IDX)*$clog2(SHIFTREG_WIDTH-1),
                        parameter NUM_LEAVES = 10,
                        parameter BRANCHES_PER_LEVEL = 3
                        )(
                        input wire clk, 
                        input wire start,
                        input wire setting_rd_en,
                        input wire [SETTING_WIDTH-1:0] setting_in,
                        output reg [SETTING_WIDTH-1:0] setting_out = 0,
                        output wire idle,
                        output reg running = 0,
                        output wire success);

    //  Parameters for tree generation.
    localparam real LEVELS_NEEDED = $rtoi($ceil($log10(NUM_LEAVES)/$log10(BRANCHES_PER_LEVEL))); // Logarithm change of base
    localparam real LARGEST_SUBBRANCH = (LEVELS_NEEDED == 0) ? NUM_LEAVES : $pow(BRANCHES_PER_LEVEL, LEVELS_NEEDED-1);
    localparam integer BRANCHES_THIS_LEVEL = NUM_LEAVES <= BRANCHES_PER_LEVEL ? NUM_LEAVES : $rtoi($ceil(NUM_LEAVES/LARGEST_SUBBRANCH));
    
    reg [SETTING_WIDTH-1:0] setting_reg = 0;
    reg setting_valid = 0;
    reg setting_out_valid = 0;
    assign idle = ~setting_valid;
    assign success = setting_out_valid;

    // Children signals
    wire [BRANCHES_THIS_LEVEL-1:0] idle_children;
    wire [BRANCHES_THIS_LEVEL-1:0] success_children;
    wire [BRANCHES_THIS_LEVEL-1:0] running_children;
    wire [BRANCHES_THIS_LEVEL-1:0] setting_rd_en_children;
    wire [SETTING_WIDTH-1:0] children_setting_out[BRANCHES_THIS_LEVEL-1:0];
    wire [BRANCHES_THIS_LEVEL-1:0] start_children;
    wire [BRANCHES_THIS_LEVEL-1:0] can_start;

    reg [BRANCHES_THIS_LEVEL-1:0] lowest_idle = 0;
    reg [BRANCHES_THIS_LEVEL-1:0] lowest_success = 0;

    always @(posedge clk) begin
        lowest_idle <= idle_children & (~idle_children + 1); // A trick to get the lowest set bit. Infers an adder.
        lowest_success <= success_children & (~success_children + 1); 
    end
    assign start_children = setting_valid ? lowest_idle : 0;

    // Setting out holds a setting that resulted in a success. 
    reg [SETTING_WIDTH-1:0] setting_out_next;
    integer i;
    always @(*) begin
        setting_out_next = 0;
        for (i = 0; i < BRANCHES_THIS_LEVEL; i = i + 1) begin
            if (lowest_success[i]) begin
                setting_out_next = children_setting_out[i];
            end
        end
    end
    
    assign setting_rd_en_children = setting_out_valid ? 0 : lowest_success;
    always @(posedge clk) begin
        if (setting_out_valid) begin
            if (setting_rd_en) begin
                setting_out_valid <= 0;
            end
        end else begin
            if (|setting_rd_en_children) begin
                setting_out_valid <= 1;
                setting_out <= setting_out_next;
            end
        end
    end

    always @(posedge clk) begin
        running <= (|running_children) | (|success_children);
    end

    always @(posedge clk) begin
        if (start) begin
            setting_reg <= setting_in;
            setting_valid <= 1;
        end else if (|start_children) begin // If a child is started, the buffer can no longer be taken. 
            setting_valid <= 0;
        end
    end 

    // Generate the tree using recursion
    genvar g;
    if (NUM_LEAVES <= BRANCHES_PER_LEVEL) begin
        assign running_children = ~idle_children;
        for (g = 0; g < NUM_LEAVES; g = g + 1) begin
            nlfsr_tester #(.SHIFTREG_WIDTH(SHIFTREG_WIDTH), .SETTING_WIDTH(SETTING_WIDTH), .NUM_NLIN(NUM_NLIN), .NUM_NLIN_IDX(NUM_NLIN_IDX) ) 
                nlfsr_tester_inst(.clk(clk),.start(start_children[g]), .setting_rd_en(setting_rd_en_children[g]), .setting_in(setting_reg), .idle(idle_children[g]), .success(success_children[g]), .setting_out(children_setting_out[g]));
        end
    end else begin
        for (g = 0; g < BRANCHES_THIS_LEVEL; g = g + 1) begin
            localparam NT = NUM_LEAVES - g*LARGEST_SUBBRANCH > LARGEST_SUBBRANCH ? LARGEST_SUBBRANCH : NUM_LEAVES - g*LARGEST_SUBBRANCH;
            distributor #(.NUM_LEAVES(NT), .BRANCHES_PER_LEVEL(BRANCHES_PER_LEVEL), .SHIFTREG_WIDTH(SHIFTREG_WIDTH), .SETTING_WIDTH(SETTING_WIDTH), .NUM_NLIN(NUM_NLIN), .NUM_NLIN_IDX(NUM_NLIN_IDX))
                distributor_inst(.clk(clk), .start(start_children[g]), .setting_rd_en(setting_rd_en_children[g]), .setting_in(setting_reg), .idle(idle_children[g]), .running(running_children[g]), .success(success_children[g]), .setting_out(children_setting_out[g]));
        end
    end
endmodule
