module max7219_chain_driver #(
    parameter integer CLK_DIV = 50
)(
    input  wire clk,
    input  wire reset,

    input  wire        start,
    input  wire [47:0] tx_data,

    output reg         busy,
    output reg         done,

    output reg         max_din,
    output reg         max_cs,
    output reg         max_clk
);

    // =========================================================
    // MAX7219 serial transfer
    // =========================================================
    //
    // MAX7219 command format:
    //   16 bits per device
    //   [15:8] = address
    //   [7:0]  = data
    //
    // 3-device daisy chain:
    //   total 48 bits
    //
    // This driver does NOT know low/mid/high or row mapping.
    // It only sends tx_data[47] down to tx_data[0] as MSB first.
    //
    // CS:
    //   idle high
    //   low during shifting
    //   high after 48 bits to latch data
    //
    // CLK:
    //   idle low
    //   data is prepared while CLK is low
    //   MAX7219 samples DIN on rising edge
    // =========================================================

    localparam integer TOTAL_BITS = 48;

    localparam [2:0]
        ST_IDLE     = 3'd0,
        ST_SETUP    = 3'd1,
        ST_CLK_HIGH = 3'd2,
        ST_LATCH    = 3'd3,
        ST_DONE     = 3'd4;

    reg [2:0] state;

    reg [47:0] shift_reg;
    reg [5:0]  bit_index;
    reg [31:0] clk_count;

    // =========================================================
    // Sequential FSM
    // =========================================================

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state     <= ST_IDLE;

            shift_reg <= 48'd0;
            bit_index <= 6'd0;
            clk_count <= 32'd0;

            busy      <= 1'b0;
            done      <= 1'b0;

            max_din   <= 1'b0;
            max_cs    <= 1'b1;   // idle high
            max_clk   <= 1'b0;   // idle low
        end
        else begin
            done <= 1'b0;

            case (state)

                // =================================================
                // Idle
                // =================================================
                ST_IDLE: begin
                    busy      <= 1'b0;
                    max_cs    <= 1'b1;
                    max_clk   <= 1'b0;
                    clk_count <= 32'd0;

                    if (start) begin
                        shift_reg <= tx_data;
                        bit_index <= TOTAL_BITS - 1;

                        max_din   <= tx_data[TOTAL_BITS - 1];
                        max_cs    <= 1'b0;   // start transfer
                        max_clk   <= 1'b0;

                        busy      <= 1'b1;
                        state     <= ST_SETUP;
                    end
                end

                // =================================================
                // Setup DIN while CLK is low
                // =================================================
                ST_SETUP: begin
                    busy    <= 1'b1;
                    max_cs  <= 1'b0;
                    max_clk <= 1'b0;

                    if (clk_count >= CLK_DIV - 1) begin
                        clk_count <= 32'd0;
                        max_clk   <= 1'b1;   // rising edge
                        state     <= ST_CLK_HIGH;
                    end
                    else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                // =================================================
                // Hold CLK high, then fall to low
                // =================================================
                ST_CLK_HIGH: begin
                    busy   <= 1'b1;
                    max_cs <= 1'b0;

                    if (clk_count >= CLK_DIV - 1) begin
                        clk_count <= 32'd0;
                        max_clk   <= 1'b0;   // falling edge

                        if (bit_index == 6'd0) begin
                            state <= ST_LATCH;
                        end
                        else begin
                            bit_index <= bit_index - 1'b1;
                            max_din   <= shift_reg[bit_index - 1'b1];
                            state     <= ST_SETUP;
                        end
                    end
                    else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                // =================================================
                // Raise CS to latch all 48 bits
                // =================================================
                ST_LATCH: begin
                    busy      <= 1'b1;
                    max_clk   <= 1'b0;
                    max_cs    <= 1'b1;   // latch data into MAX7219
                    clk_count <= 32'd0;

                    state     <= ST_DONE;
                end

                // =================================================
                // Done pulse
                // =================================================
                ST_DONE: begin
                    busy    <= 1'b0;
                    done    <= 1'b1;

                    max_cs  <= 1'b1;
                    max_clk <= 1'b0;

                    state   <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end

            endcase
        end
    end

endmodule