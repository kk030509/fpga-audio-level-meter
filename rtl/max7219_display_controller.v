module max7219_display_controller #(
    parameter integer POWERUP_DELAY = 5_000_000
)(
    input  wire clk,
    input  wire reset,

    input  wire frame_valid,

    input  wire driver_busy,
    input  wire driver_done,

    output reg  tx_start,
    output reg  init_mode,
    output reg  [3:0] init_step,
    output reg  [2:0] row_index
);

    // =========================================================
    // FSM states
    // =========================================================

    localparam [2:0]
        ST_POWERUP   = 3'd0,
        ST_INIT_SEND = 3'd1,
        ST_INIT_WAIT = 3'd2,
        ST_IDLE      = 3'd3,
        ST_ROW_SEND  = 3'd4,
        ST_ROW_WAIT  = 3'd5;

    reg [2:0] state;

    // =========================================================
    // Counters / flags
    // =========================================================

    reg [31:0] powerup_count;
    reg        frame_pending;

    // init_step:
    //   0~4  : MAX7219 setup commands
    //   5~12 : clear row 1~8
    localparam [3:0] INIT_LAST_STEP = 4'd12;

    // row_index:
    //   0~7 maps to MAX7219 row address 1~8 in display_engine
    localparam [2:0] ROW_LAST = 3'd7;

    // =========================================================
    // Sequential FSM
    // =========================================================

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state         <= ST_POWERUP;

            powerup_count <= 32'd0;
            frame_pending <= 1'b0;

            tx_start      <= 1'b0;
            init_mode     <= 1'b1;
            init_step     <= 4'd0;
            row_index     <= 3'd0;
        end
        else begin
            // tx_start는 1클럭 pulse
            tx_start <= 1'b0;

            // display update 요청 저장
            if (frame_valid) begin
                frame_pending <= 1'b1;
            end

            case (state)

                // =================================================
                // Wait after power-up
                // =================================================
                ST_POWERUP: begin
                    init_mode <= 1'b1;
                    init_step <= 4'd0;
                    row_index <= 3'd0;

                    if (powerup_count >= POWERUP_DELAY - 1) begin
                        powerup_count <= 32'd0;
                        state         <= ST_INIT_SEND;
                    end
                    else begin
                        powerup_count <= powerup_count + 1'b1;
                    end
                end

                // =================================================
                // Send one init command
                // =================================================
                ST_INIT_SEND: begin
                    init_mode <= 1'b1;

                    if (!driver_busy) begin
                        tx_start <= 1'b1;
                        state    <= ST_INIT_WAIT;
                    end
                end

                // =================================================
                // Wait until chain driver finishes current init cmd
                // =================================================
                ST_INIT_WAIT: begin
                    init_mode <= 1'b1;

                    if (driver_done) begin
                        if (init_step == INIT_LAST_STEP) begin
                            init_step <= 4'd0;
                            state     <= ST_IDLE;
                        end
                        else begin
                            init_step <= init_step + 1'b1;
                            state     <= ST_INIT_SEND;
                        end
                    end
                end

                // =================================================
                // Idle until a new display frame is available
                // =================================================
                ST_IDLE: begin
                    init_mode <= 1'b0;
                    row_index <= 3'd0;

                    if (frame_pending && !driver_busy) begin
                        frame_pending <= 1'b0;
                        state         <= ST_ROW_SEND;
                    end
                end

                // =================================================
                // Send one display row command
                // =================================================
                ST_ROW_SEND: begin
                    init_mode <= 1'b0;

                    if (!driver_busy) begin
                        tx_start <= 1'b1;
                        state    <= ST_ROW_WAIT;
                    end
                end

                // =================================================
                // Wait until current row transmission is complete
                // =================================================
                ST_ROW_WAIT: begin
                    init_mode <= 1'b0;

                    if (driver_done) begin
                        if (row_index == ROW_LAST) begin
                            row_index <= 3'd0;
                            state     <= ST_IDLE;
                        end
                        else begin
                            row_index <= row_index + 1'b1;
                            state     <= ST_ROW_SEND;
                        end
                    end
                end

                default: begin
                    state <= ST_POWERUP;
                end

            endcase
        end
    end

endmodule