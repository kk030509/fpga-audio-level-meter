module audio_level_meter_top (
    input  wire clk,
    input  wire btnU,

    // MAX7219 control signals
    output wire JA2,   // DIN
    output wire JA3,   // CS / LOAD
    output wire JA4,   // CLK

    // PCM5102A I2S signals
    // XDC:
    //   i2s_bck  -> M18
    //   i2s_dout -> N17
    //   i2s_lrck -> P18
    output wire i2s_sck,
    output wire i2s_bck,
    output wire i2s_dout,
    output wire i2s_lck
);

    // =========================================================
    // Reset
    // =========================================================

    wire reset;
    assign reset = btnU;

    // =========================================================
    // System parameters
    // =========================================================

    localparam integer AUDIO_DEPTH = 64000;

    localparam integer WINDOW_SIZE      = 512;
    localparam integer ENERGY_FRAC_BITS = 4;

    localparam signed [15:0] LOW_COEF_Q15  = 16'sd5842;
    localparam signed [15:0] HIGH_COEF_Q15 = 16'sd22680;

    localparam integer I2S_DATA_WIDTH    = 16;
    localparam integer I2S_BCLK_HALF_DIV = 195;

    localparam integer MAX7219_CLK_DIV       = 50;
    localparam integer MAX7219_POWERUP_DELAY = 5_000_000;

    // =========================================================
    // Hard minimum reference values for RTL auto calibration
    // =========================================================
    //
    // band_auto_level_mapper learns low/mid/high reference values
    // during the first playback loop.
    //
    // These MIN_REF values are not fixed final display references.
    // They are safety floors that prevent the learned reference from
    // becoming too small due to weak signal or noise.
    //
    // learned_ref = max(observed_peak, MIN_REF)
    //
    // Q4 scale:
    //   16'd128 = actual average 8.0
    //   16'd96  = actual average 6.0
    //   16'd64  = actual average 4.0
    // =========================================================
    localparam [15:0] LOW_MIN_REF  = 16'd128;
    localparam [15:0] MID_MIN_REF  = 16'd96;
    localparam [15:0] HIGH_MIN_REF = 16'd64;

    localparam integer REF_DECAY_SHIFT = 5;

    // =========================================================
    // Audio sample reader
    // =========================================================

    wire        sample_req;
    wire        sample_valid;
    wire [7:0]  rom_sample;

    audio_sample_reader #(
        .DEPTH   (AUDIO_DEPTH),
        .MEMFILE ("audio_8k_s8.mem")
    ) u_audio_sample_reader (
        .clk          (clk),
        .reset        (reset),
        .sample_req   (sample_req),
        .sample_out   (rom_sample),
        .sample_valid (sample_valid)
    );

    // =========================================================
    // PCM sample format
    // =========================================================
    //
    // audio_8k_s8.mem은 signed 8-bit PCM이다.
    //
    // pcm_filter:
    //   RTL 필터 입력용 signed 16-bit 확장
    //
    // pcm_i2s:
    //   I2S 출력용 signed 16-bit 변환
    //   signed 8-bit sample을 상위 8비트에 두고 하위 8비트를 0으로 채운다.
    // =========================================================

    wire signed [15:0] pcm_filter;
    wire signed [15:0] pcm_i2s;

    assign pcm_filter = {{8{rom_sample[7]}}, rom_sample};
    assign pcm_i2s    = {rom_sample, 8'h00};

    // =========================================================
    // I2S transmitter
    // =========================================================
    //
    // XDC 포트 이름과 일치:
    //   i2s_bck
    //   i2s_dout
    //   i2s_lrck
    // =========================================================

    i2s_transmitter #(
        .DATA_WIDTH    (I2S_DATA_WIDTH),
        .BCLK_HALF_DIV (I2S_BCLK_HALF_DIV)
    ) u_i2s_transmitter (
        .clk        (clk),
        .reset      (reset),
        .sample_in  (pcm_i2s),
        .sample_req (sample_req),

        .i2s_sck    (i2s_sck),
        .i2s_bck    (i2s_bck),
        .i2s_dout   (i2s_dout),
        .i2s_lck   (i2s_lck)
    );

    // =========================================================
    // Audio band splitter
    // =========================================================

    wire signed [15:0] low_sample;
    wire signed [15:0] mid_sample;
    wire signed [15:0] high_sample;
    wire               band_valid;

    audio_band_splitter #(
        .LOW_COEF_Q15  (LOW_COEF_Q15),
        .HIGH_COEF_Q15 (HIGH_COEF_Q15)
    ) u_audio_band_splitter (
        .clk          (clk),
        .reset        (reset),
        .pcm_sample   (pcm_filter),
        .sample_valid (sample_valid),

        .low_sample   (low_sample),
        .mid_sample   (mid_sample),
        .high_sample  (high_sample),
        .band_valid   (band_valid)
    );

    // =========================================================
    // Band energy meter
    // =========================================================

    wire [15:0] low_avg;
    wire [15:0] mid_avg;
    wire [15:0] high_avg;
    wire        avg_valid;

    band_energy_meter #(
        .WINDOW_SIZE      (WINDOW_SIZE),
        .ENERGY_FRAC_BITS (ENERGY_FRAC_BITS)
    ) u_band_energy_meter (
        .clk         (clk),
        .reset       (reset),

        .low_sample  (low_sample),
        .mid_sample  (mid_sample),
        .high_sample (high_sample),
        .band_valid  (band_valid),

        .low_avg     (low_avg),
        .mid_avg     (mid_avg),
        .high_avg    (high_avg),
        .avg_valid   (avg_valid)
    );

    // =========================================================
    // Adaptive level mapper
    // =========================================================

    wire [3:0] low_level;
    wire [3:0] mid_level;
    wire [3:0] high_level;
    wire       level_valid;

    band_auto_level_mapper #(
        .LOW_MIN_REF  (LOW_MIN_REF),
        .MID_MIN_REF  (MID_MIN_REF),
        .HIGH_MIN_REF (HIGH_MIN_REF),
        .DECAY_SHIFT  (REF_DECAY_SHIFT)
    ) u_band_auto_level_mapper (
        .clk         (clk),
        .reset       (reset),

        .low_avg     (low_avg),
        .mid_avg     (mid_avg),
        .high_avg    (high_avg),
        .avg_valid   (avg_valid),

        .low_level   (low_level),
        .mid_level   (mid_level),
        .high_level  (high_level),
        .level_valid (level_valid)
    );

    // =========================================================
    // Matrix level history
    // =========================================================

    wire [63:0] low_frame;
    wire [63:0] mid_frame;
    wire [63:0] high_frame;
    wire        frame_valid;

    matrix_level_history u_matrix_level_history (
        .clk         (clk),
        .reset       (reset),

        .low_level   (low_level),
        .mid_level   (mid_level),
        .high_level  (high_level),
        .level_valid (level_valid),

        .low_frame   (low_frame),
        .mid_frame   (mid_frame),
        .high_frame  (high_frame),
        .frame_valid (frame_valid)
    );

    // =========================================================
    // MAX7219 display control
    // =========================================================

    wire        max_start;
    wire [47:0] max_tx_data;
    wire        max_busy;
    wire        max_done;

    wire        display_init_mode;
    wire [3:0]  display_init_step;
    wire [2:0]  display_row_index;

    max7219_display_controller #(
        .POWERUP_DELAY (MAX7219_POWERUP_DELAY)
    ) u_max7219_display_controller (
        .clk            (clk),
        .reset          (reset),

        .frame_valid    (frame_valid),

        .driver_busy    (max_busy),
        .driver_done    (max_done),

        .tx_start       (max_start),
        .init_mode      (display_init_mode),
        .init_step      (display_init_step),
        .row_index      (display_row_index)
    );

    max7219_display_engine u_max7219_display_engine (
        .init_mode  (display_init_mode),
        .init_step  (display_init_step),
        .row_index  (display_row_index),

        .low_frame  (low_frame),
        .mid_frame  (mid_frame),
        .high_frame (high_frame),

        .tx_data    (max_tx_data)
    );

    max7219_chain_driver #(
        .CLK_DIV (MAX7219_CLK_DIV)
    ) u_max7219_chain_driver (
        .clk     (clk),
        .reset   (reset),

        .start   (max_start),
        .tx_data (max_tx_data),

        .busy    (max_busy),
        .done    (max_done),

        .max_din (JA2),
        .max_cs  (JA3),
        .max_clk (JA4)
    );

endmodule