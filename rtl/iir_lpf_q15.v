module iir_lpf_q15 #(
    parameter signed [15:0] COEF_Q15 = 16'sd5842
)(
    input  wire clk,
    input  wire reset,

    input  wire signed [15:0] sample_in,
    input  wire               sample_valid,

    output reg  signed [15:0] sample_out,
    output reg                sample_valid_out
);

    // =========================================================
    // Pipelined Q15 IIR low-pass filter
    // =========================================================
    //
    // Difference equation:
    //
    //   y[n] = y[n-1] + alpha * (x[n] - y[n-1])
    //
    // Q15 fixed-point:
    //
    //   diff   = x - y
    //   mult   = diff * COEF_Q15
    //   delta  = mult >>> 15
    //   y_next = y + delta
    //
    // Timing improvement:
    //
    // Previous version calculated diff, multiply, shift, and add
    // in one 100 MHz clock cycle.
    //
    // This version splits the calculation into multiple stages:
    //
    //   cycle 0: capture diff
    //   cycle 1: multiply
    //   cycle 2: shift
    //   cycle 3: update y_state and output valid
    //
    // Since audio sample_valid occurs at about 8 kHz, this few-cycle
    // latency is negligible for the audio level meter.
    // =========================================================

    // Current filter state
    reg signed [15:0] y_state;

    // Pipeline valid flags
    reg valid_s1;
    reg valid_s2;
    reg valid_s3;

    // Stage registers
    reg signed [16:0] diff_s1;
    reg signed [32:0] mult_s2;
    reg signed [17:0] delta_s3;

    // Stage 0 combinational helpers
    wire signed [16:0] x_ext;
    wire signed [16:0] y_ext;
    wire signed [16:0] diff_next;

    assign x_ext     = {sample_in[15], sample_in};
    assign y_ext     = {y_state[15],  y_state};
    assign diff_next = x_ext - y_ext;

    // Stage 2 / 3 helpers
    wire signed [17:0] y_ext_18;
    wire signed [17:0] y_next_ext;
    wire signed [15:0] y_next;

    assign y_ext_18   = {{2{y_state[15]}}, y_state};
    assign y_next_ext = y_ext_18 + delta_s3;
    assign y_next     = y_next_ext[15:0];

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            y_state          <= 16'sd0;
            sample_out       <= 16'sd0;
            sample_valid_out <= 1'b0;

            valid_s1         <= 1'b0;
            valid_s2         <= 1'b0;
            valid_s3         <= 1'b0;

            diff_s1          <= 17'sd0;
            mult_s2          <= 33'sd0;
            delta_s3         <= 18'sd0;
        end
        else begin
            // Default output valid pulse
            sample_valid_out <= 1'b0;

            // Valid pipeline
            valid_s1 <= sample_valid;
            valid_s2 <= valid_s1;
            valid_s3 <= valid_s2;

            // =================================================
            // Stage 1: capture diff
            // =================================================
            if (sample_valid) begin
                diff_s1 <= diff_next;
            end

            // =================================================
            // Stage 2: multiply
            // =================================================
            if (valid_s1) begin
                mult_s2 <= diff_s1 * COEF_Q15;
            end

            // =================================================
            // Stage 3: shift
            // =================================================
            if (valid_s2) begin
                delta_s3 <= mult_s2 >>> 15;
            end

            // =================================================
            // Stage 4: update state and output
            // =================================================
            if (valid_s3) begin
                y_state          <= y_next;
                sample_out       <= y_next;
                sample_valid_out <= 1'b1;
            end
        end
    end

endmodule