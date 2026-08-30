module band_energy_meter #(
    parameter integer WINDOW_SIZE      = 512,
    parameter integer ENERGY_FRAC_BITS = 4
)(
    input  wire clk,
    input  wire reset,

    input  wire signed [15:0] low_sample,
    input  wire signed [15:0] mid_sample,
    input  wire signed [15:0] high_sample,
    input  wire               band_valid,

    output reg  [15:0] low_avg,
    output reg  [15:0] mid_avg,
    output reg  [15:0] high_avg,
    output reg         avg_valid
);

    // =========================================================
    // Local parameters
    // =========================================================

    localparam integer WINDOW_SHIFT = $clog2(WINDOW_SIZE);
    localparam integer AVG_SHIFT    = WINDOW_SHIFT - ENERGY_FRAC_BITS;

    // WINDOW_SIZE = 512, ENERGY_FRAC_BITS = 4 기준:
    // WINDOW_SHIFT = 9
    // AVG_SHIFT    = 5
    //
    // 기존 평균:
    //   avg = sum >> 9
    //
    // 수정 후 Q4 scaled average:
    //   avg_q4 = sum >> 5
    //          = sum / 512 * 16

    // =========================================================
    // Absolute value
    // =========================================================

    wire [15:0] low_abs;
    wire [15:0] mid_abs;
    wire [15:0] high_abs;

    assign low_abs  = low_sample[15]  ? (~low_sample  + 16'd1) : low_sample;
    assign mid_abs  = mid_sample[15]  ? (~mid_sample  + 16'd1) : mid_sample;
    assign high_abs = high_sample[15] ? (~high_sample + 16'd1) : high_sample;

    // =========================================================
    // Accumulators
    // =========================================================

    reg [31:0] low_sum;
    reg [31:0] mid_sum;
    reg [31:0] high_sum;

    reg [WINDOW_SHIFT-1:0] sample_count;

    wire [31:0] low_sum_next;
    wire [31:0] mid_sum_next;
    wire [31:0] high_sum_next;

    assign low_sum_next  = low_sum  + {16'd0, low_abs};
    assign mid_sum_next  = mid_sum  + {16'd0, mid_abs};
    assign high_sum_next = high_sum + {16'd0, high_abs};

    // =========================================================
    // Window average
    // =========================================================

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            low_sum      <= 32'd0;
            mid_sum      <= 32'd0;
            high_sum     <= 32'd0;
            sample_count <= {WINDOW_SHIFT{1'b0}};

            low_avg      <= 16'd0;
            mid_avg      <= 16'd0;
            high_avg     <= 16'd0;
            avg_valid    <= 1'b0;
        end
        else begin
            avg_valid <= 1'b0;

            if (band_valid) begin
                if (sample_count == WINDOW_SIZE - 1) begin
                    // Include current sample, then calculate Q4 scaled average.
                    low_avg  <= low_sum_next  >> AVG_SHIFT;
                    mid_avg  <= mid_sum_next  >> AVG_SHIFT;
                    high_avg <= high_sum_next >> AVG_SHIFT;

                    avg_valid <= 1'b1;

                    low_sum      <= 32'd0;
                    mid_sum      <= 32'd0;
                    high_sum     <= 32'd0;
                    sample_count <= {WINDOW_SHIFT{1'b0}};
                end
                else begin
                    low_sum      <= low_sum_next;
                    mid_sum      <= mid_sum_next;
                    high_sum     <= high_sum_next;
                    sample_count <= sample_count + 1'b1;
                end
            end
        end
    end

endmodule