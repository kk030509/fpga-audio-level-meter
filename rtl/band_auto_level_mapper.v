module band_auto_level_mapper #(
    // =========================================================
    // Hard minimum reference values
    // =========================================================
    //
    // band_energy_meter outputs Q4 scaled average values.
    //
    //   avg_q4 = actual_average * 16
    //
    // Therefore:
    //
    //   16'd128 = actual average 8.0
    //   16'd96  = actual average 6.0
    //   16'd64  = actual average 4.0
    //
    // These values are NOT fixed final display references.
    // They are safety floors for RTL auto calibration.
    //
    // learned_ref = max(observed_peak, hard_min_ref)
    // =========================================================

    parameter [15:0] LOW_MIN_REF  = 16'd128,
    parameter [15:0] MID_MIN_REF  = 16'd96,
    parameter [15:0] HIGH_MIN_REF = 16'd64,

    // Current project:
    //   AUDIO_DEPTH = 64000
    //   WINDOW_SIZE = 512
    //   CALIB_WINDOWS = 64000 / 512 = 125
    parameter integer CALIB_WINDOWS = 125,

    // Reference decay speed after calibration.
    parameter integer DECAY_SHIFT = 5
)(
    input  wire clk,
    input  wire reset,

    input  wire [15:0] low_avg,
    input  wire [15:0] mid_avg,
    input  wire [15:0] high_avg,
    input  wire        avg_valid,

    output reg  [3:0]  low_level,
    output reg  [3:0]  mid_level,
    output reg  [3:0]  high_level,
    output reg         level_valid
);

    // =========================================================
    // Calibration / reference registers
    // =========================================================

    reg        calibration_done;
    reg [15:0] calib_count;

    reg [15:0] low_peak;
    reg [15:0] mid_peak;
    reg [15:0] high_peak;

    reg [15:0] low_base_ref;
    reg [15:0] mid_base_ref;
    reg [15:0] high_base_ref;

    reg [15:0] low_ref;
    reg [15:0] mid_ref;
    reg [15:0] high_ref;

    // =========================================================
    // Pipeline registers
    // =========================================================
    //
    // Previous version calculated:
    //
    //   avg -> peak/ref update -> level calculation -> level register
    //
    // in one clock cycle.
    //
    // This version separates it:
    //
    //   stage 1:
    //     avg capture
    //     peak/ref update
    //     select ref_for_level
    //
    //   stage 2:
    //     calculate level from registered avg/ref
    //
    // avg_valid occurs only once per 512 samples, so this 1-clock
    // latency has no visible impact on the display.
    // =========================================================

    reg        level_stage_valid;

    reg [15:0] low_avg_stage;
    reg [15:0] mid_avg_stage;
    reg [15:0] high_avg_stage;

    reg [15:0] low_ref_stage;
    reg [15:0] mid_ref_stage;
    reg [15:0] high_ref_stage;

    // =========================================================
    // Helper: max
    // =========================================================

    function [15:0] max16;
        input [15:0] a;
        input [15:0] b;
        begin
            if (a > b)
                max16 = a;
            else
                max16 = b;
        end
    endfunction

    // =========================================================
    // Helper: reference update
    // =========================================================
    //
    // avg > ref:
    //   ref immediately follows the stronger energy.
    //
    // avg <= ref:
    //   ref decays slowly.
    //
    // ref never goes below min_ref.
    // =========================================================

    function [15:0] update_ref;
        input [15:0] avg;
        input [15:0] ref;
        input [15:0] min_ref;

        reg [15:0] decayed_ref;

        begin
            if (avg > ref) begin
                update_ref = avg;
            end
            else begin
                decayed_ref = ref - (ref >> DECAY_SHIFT);

                if (decayed_ref < min_ref)
                    update_ref = min_ref;
                else
                    update_ref = decayed_ref;
            end
        end
    endfunction

    // =========================================================
    // Helper: level calculation
    // =========================================================
    //
    // level 8 : avg >= ref * 8/8
    // level 7 : avg >= ref * 7/8
    // ...
    // level 1 : avg >= ref * 1/8
    //
    // Division is avoided:
    //
    //   avg * 8 >= ref * level
    // =========================================================

    function [3:0] calc_level;
        input [15:0] avg;
        input [15:0] ref;

        reg [18:0] avg_x8;
        reg [18:0] ref_ext;

        begin
            avg_x8  = {avg, 3'b000};      // avg * 8
            ref_ext = {3'b000, ref};

            if (avg == 16'd0) begin
                calc_level = 4'd0;
            end
            else if (avg_x8 >= (ref_ext << 3)) begin
                calc_level = 4'd8;
            end
            else if (avg_x8 >= ((ref_ext << 3) - ref_ext)) begin
                calc_level = 4'd7;
            end
            else if (avg_x8 >= ((ref_ext << 2) + (ref_ext << 1))) begin
                calc_level = 4'd6;
            end
            else if (avg_x8 >= ((ref_ext << 2) + ref_ext)) begin
                calc_level = 4'd5;
            end
            else if (avg_x8 >= (ref_ext << 2)) begin
                calc_level = 4'd4;
            end
            else if (avg_x8 >= ((ref_ext << 1) + ref_ext)) begin
                calc_level = 4'd3;
            end
            else if (avg_x8 >= (ref_ext << 1)) begin
                calc_level = 4'd2;
            end
            else if (avg_x8 >= ref_ext) begin
                calc_level = 4'd1;
            end
            else begin
                calc_level = 4'd0;
            end
        end
    endfunction

    // =========================================================
    // Combinational next values
    // =========================================================

    wire [15:0] low_peak_next;
    wire [15:0] mid_peak_next;
    wire [15:0] high_peak_next;

    assign low_peak_next  = max16(low_peak,  low_avg);
    assign mid_peak_next  = max16(mid_peak,  mid_avg);
    assign high_peak_next = max16(high_peak, high_avg);

    wire [15:0] low_final_ref;
    wire [15:0] mid_final_ref;
    wire [15:0] high_final_ref;

    assign low_final_ref  = max16(low_peak_next,  LOW_MIN_REF);
    assign mid_final_ref  = max16(mid_peak_next,  MID_MIN_REF);
    assign high_final_ref = max16(high_peak_next, HIGH_MIN_REF);

    wire [15:0] low_ref_next;
    wire [15:0] mid_ref_next;
    wire [15:0] high_ref_next;

    assign low_ref_next  = update_ref(low_avg,  low_ref,  low_base_ref);
    assign mid_ref_next  = update_ref(mid_avg,  mid_ref,  mid_base_ref);
    assign high_ref_next = update_ref(high_avg, high_ref, high_base_ref);

    // =========================================================
    // Main sequential logic
    // =========================================================

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            calibration_done <= 1'b0;
            calib_count      <= 16'd0;

            low_peak         <= 16'd0;
            mid_peak         <= 16'd0;
            high_peak        <= 16'd0;

            low_base_ref     <= LOW_MIN_REF;
            mid_base_ref     <= MID_MIN_REF;
            high_base_ref    <= HIGH_MIN_REF;

            low_ref          <= LOW_MIN_REF;
            mid_ref          <= MID_MIN_REF;
            high_ref         <= HIGH_MIN_REF;

            low_avg_stage    <= 16'd0;
            mid_avg_stage    <= 16'd0;
            high_avg_stage   <= 16'd0;

            low_ref_stage    <= LOW_MIN_REF;
            mid_ref_stage    <= MID_MIN_REF;
            high_ref_stage   <= HIGH_MIN_REF;

            level_stage_valid <= 1'b0;

            low_level        <= 4'd0;
            mid_level        <= 4'd0;
            high_level       <= 4'd0;
            level_valid      <= 1'b0;
        end
        else begin
            // Default pulses
            level_valid       <= 1'b0;
            level_stage_valid <= 1'b0;

            // =================================================
            // Stage 2:
            // Calculate level from registered avg/ref.
            // This uses values captured in the previous cycle.
            // =================================================

            if (level_stage_valid) begin
                low_level   <= calc_level(low_avg_stage,  low_ref_stage);
                mid_level   <= calc_level(mid_avg_stage,  mid_ref_stage);
                high_level  <= calc_level(high_avg_stage, high_ref_stage);
                level_valid <= 1'b1;
            end

            // =================================================
            // Stage 1:
            // Capture avg and select/update reference.
            // =================================================

            if (avg_valid) begin
                low_avg_stage  <= low_avg;
                mid_avg_stage  <= mid_avg;
                high_avg_stage <= high_avg;

                level_stage_valid <= 1'b1;

                // ---------------------------------------------
                // Calibration phase
                // ---------------------------------------------
                if (!calibration_done) begin
                    low_peak  <= low_peak_next;
                    mid_peak  <= mid_peak_next;
                    high_peak <= high_peak_next;

                    if (calib_count == CALIB_WINDOWS - 1) begin
                        // Finish calibration.
                        low_base_ref  <= low_final_ref;
                        mid_base_ref  <= mid_final_ref;
                        high_base_ref <= high_final_ref;

                        low_ref       <= low_final_ref;
                        mid_ref       <= mid_final_ref;
                        high_ref      <= high_final_ref;

                        low_ref_stage  <= low_final_ref;
                        mid_ref_stage  <= mid_final_ref;
                        high_ref_stage <= high_final_ref;

                        calibration_done <= 1'b1;
                        calib_count      <= 16'd0;
                    end
                    else begin
                        // Provisional display during first loop.
                        low_ref_stage  <= LOW_MIN_REF;
                        mid_ref_stage  <= MID_MIN_REF;
                        high_ref_stage <= HIGH_MIN_REF;

                        calib_count <= calib_count + 1'b1;
                    end
                end

                // ---------------------------------------------
                // Normal adaptive phase
                // ---------------------------------------------
                else begin
                    low_ref  <= low_ref_next;
                    mid_ref  <= mid_ref_next;
                    high_ref <= high_ref_next;

                    low_ref_stage  <= low_ref_next;
                    mid_ref_stage  <= mid_ref_next;
                    high_ref_stage <= high_ref_next;
                end
            end
        end
    end

endmodule