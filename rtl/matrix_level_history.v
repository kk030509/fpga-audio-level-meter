module matrix_level_history (
    input  wire clk,
    input  wire reset,

    input  wire [3:0] low_level,
    input  wire [3:0] mid_level,
    input  wire [3:0] high_level,
    input  wire       level_valid,

    output reg  [63:0] low_frame,
    output reg  [63:0] mid_frame,
    output reg  [63:0] high_frame,
    output reg         frame_valid
);

    // =========================================================
    // Frame mapping
    // =========================================================
    //
    // frame[7:0]    = row 0, top row
    // frame[15:8]   = row 1
    // ...
    // frame[63:56]  = row 7, bottom row
    //
    // Each row:
    //   bit 7 = leftmost column, newest value
    //   bit 0 = rightmost column, oldest value
    //
    // New level is inserted into bit 7.
    // Previous history shifts right.
    //
    // level 0 = no row ON
    // level 1 = bottom row only
    // level 8 = all rows ON
    // =========================================================

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            low_frame   <= 64'd0;
            mid_frame   <= 64'd0;
            high_frame  <= 64'd0;
            frame_valid <= 1'b0;
        end
        else begin
            frame_valid <= 1'b0;

            if (level_valid) begin
                // =================================================
                // Row 0: top row, threshold level 8
                // =================================================
                low_frame[7:0]   <= { (low_level  >= 4'd8), low_frame[7:1] };
                mid_frame[7:0]   <= { (mid_level  >= 4'd8), mid_frame[7:1] };
                high_frame[7:0]  <= { (high_level >= 4'd8), high_frame[7:1] };

                // =================================================
                // Row 1: threshold level 7
                // =================================================
                low_frame[15:8]  <= { (low_level  >= 4'd7), low_frame[15:9] };
                mid_frame[15:8]  <= { (mid_level  >= 4'd7), mid_frame[15:9] };
                high_frame[15:8] <= { (high_level >= 4'd7), high_frame[15:9] };

                // =================================================
                // Row 2: threshold level 6
                // =================================================
                low_frame[23:16]  <= { (low_level  >= 4'd6), low_frame[23:17] };
                mid_frame[23:16]  <= { (mid_level  >= 4'd6), mid_frame[23:17] };
                high_frame[23:16] <= { (high_level >= 4'd6), high_frame[23:17] };

                // =================================================
                // Row 3: threshold level 5
                // =================================================
                low_frame[31:24]  <= { (low_level  >= 4'd5), low_frame[31:25] };
                mid_frame[31:24]  <= { (mid_level  >= 4'd5), mid_frame[31:25] };
                high_frame[31:24] <= { (high_level >= 4'd5), high_frame[31:25] };

                // =================================================
                // Row 4: threshold level 4
                // =================================================
                low_frame[39:32]  <= { (low_level  >= 4'd4), low_frame[39:33] };
                mid_frame[39:32]  <= { (mid_level  >= 4'd4), mid_frame[39:33] };
                high_frame[39:32] <= { (high_level >= 4'd4), high_frame[39:33] };

                // =================================================
                // Row 5: threshold level 3
                // =================================================
                low_frame[47:40]  <= { (low_level  >= 4'd3), low_frame[47:41] };
                mid_frame[47:40]  <= { (mid_level  >= 4'd3), mid_frame[47:41] };
                high_frame[47:40] <= { (high_level >= 4'd3), high_frame[47:41] };

                // =================================================
                // Row 6: threshold level 2
                // =================================================
                low_frame[55:48]  <= { (low_level  >= 4'd2), low_frame[55:49] };
                mid_frame[55:48]  <= { (mid_level  >= 4'd2), mid_frame[55:49] };
                high_frame[55:48] <= { (high_level >= 4'd2), high_frame[55:49] };

                // =================================================
                // Row 7: bottom row, threshold level 1
                // =================================================
                low_frame[63:56]  <= { (low_level  >= 4'd1), low_frame[63:57] };
                mid_frame[63:56]  <= { (mid_level  >= 4'd1), mid_frame[63:57] };
                high_frame[63:56] <= { (high_level >= 4'd1), high_frame[63:57] };

                frame_valid <= 1'b1;
            end
        end
    end

endmodule