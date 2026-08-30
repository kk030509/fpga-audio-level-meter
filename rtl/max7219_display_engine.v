module max7219_display_engine #(
    parameter ROTATE_180 = 1
)(
    input  wire        init_mode,
    input  wire [3:0]  init_step,
    input  wire [2:0]  row_index,

    input  wire [63:0] low_frame,
    input  wire [63:0] mid_frame,
    input  wire [63:0] high_frame,

    output reg  [47:0] tx_data
);

    // =========================================================
    // MAX7219 command format
    // =========================================================
    //
    // One MAX7219 command:
    //   [15:8] = address
    //   [7:0]  = data
    //
    // Daisy chain order:
    //   tx_data[47:32] -> 3rd module, High
    //   tx_data[31:16] -> 2nd module, Mid
    //   tx_data[15:0]  -> 1st module, Low
    //
    // Therefore:
    //   tx_data = {high_cmd, mid_cmd, low_cmd}
    // =========================================================

    // =========================================================
    // Command helper
    // =========================================================

    function [15:0] make_cmd;
        input [7:0] addr;
        input [7:0] data;
        begin
            make_cmd = {addr, data};
        end
    endfunction

    // =========================================================
    // Bit reverse helper
    // =========================================================
    //
    // Used for 180-degree display rotation.
    // =========================================================

    function [7:0] reverse8;
        input [7:0] din;
        begin
            reverse8[7] = din[0];
            reverse8[6] = din[1];
            reverse8[5] = din[2];
            reverse8[4] = din[3];
            reverse8[3] = din[4];
            reverse8[2] = din[5];
            reverse8[1] = din[6];
            reverse8[0] = din[7];
        end
    endfunction

    // =========================================================
    // Frame row read helper
    // =========================================================
    //
    // frame[row*8 +: 8]
    //
    // row 0 = top logical row
    // row 7 = bottom logical row
    // bit 7 = leftmost column
    // bit 0 = rightmost column
    // =========================================================

    function [7:0] get_row;
        input [63:0] frame;
        input [2:0]  row;
        begin
            case (row)
                3'd0: get_row = frame[7:0];
                3'd1: get_row = frame[15:8];
                3'd2: get_row = frame[23:16];
                3'd3: get_row = frame[31:24];
                3'd4: get_row = frame[39:32];
                3'd5: get_row = frame[47:40];
                3'd6: get_row = frame[55:48];
                3'd7: get_row = frame[63:56];
                default: get_row = 8'h00;
            endcase
        end
    endfunction

    // =========================================================
    // Row mapping
    // =========================================================
    //
    // Normal:
    //   send logical row_index directly.
    //
    // ROTATE_180:
    //   send logical row 7-row_index and reverse column bits.
    //
    // This compensates for dot-matrix modules mounted upside down.
    // =========================================================

    function [7:0] get_mapped_row;
        input [63:0] frame;
        input [2:0]  row;
        reg   [2:0]  mapped_row;
        reg   [7:0]  row_data;
        begin
            if (ROTATE_180) begin
                mapped_row     = 3'd7 - row;
                row_data       = get_row(frame, mapped_row);
                get_mapped_row = reverse8(row_data);
            end
            else begin
                get_mapped_row = get_row(frame, row);
            end
        end
    endfunction

    // =========================================================
    // Init command generation
    // =========================================================

    reg [15:0] init_cmd;

    always @(*) begin
        case (init_step)
            4'd0: init_cmd = make_cmd(8'h0F, 8'h00); // Display test off
            4'd1: init_cmd = make_cmd(8'h09, 8'h00); // Decode mode off
            4'd2: init_cmd = make_cmd(8'h0B, 8'h07); // Scan limit: 8 digits
            4'd3: init_cmd = make_cmd(8'h0A, 8'h03); // Intensity
            4'd4: init_cmd = make_cmd(8'h0C, 8'h01); // Normal operation

            // Clear display rows
            4'd5: init_cmd = make_cmd(8'h01, 8'h00);
            4'd6: init_cmd = make_cmd(8'h02, 8'h00);
            4'd7: init_cmd = make_cmd(8'h03, 8'h00);
            4'd8: init_cmd = make_cmd(8'h04, 8'h00);
            4'd9: init_cmd = make_cmd(8'h05, 8'h00);
            4'd10: init_cmd = make_cmd(8'h06, 8'h00);
            4'd11: init_cmd = make_cmd(8'h07, 8'h00);
            4'd12: init_cmd = make_cmd(8'h08, 8'h00);

            default: init_cmd = make_cmd(8'h00, 8'h00);
        endcase
    end

    // =========================================================
    // Display row command generation
    // =========================================================

    wire [7:0] row_addr;

    wire [7:0] low_row_data;
    wire [7:0] mid_row_data;
    wire [7:0] high_row_data;

    wire [15:0] low_cmd;
    wire [15:0] mid_cmd;
    wire [15:0] high_cmd;

    assign row_addr = {5'b00000, row_index} + 8'd1;

    assign low_row_data  = get_mapped_row(low_frame,  row_index);
    assign mid_row_data  = get_mapped_row(mid_frame,  row_index);
    assign high_row_data = get_mapped_row(high_frame, row_index);

    assign low_cmd  = make_cmd(row_addr, low_row_data);
    assign mid_cmd  = make_cmd(row_addr, mid_row_data);
    assign high_cmd = make_cmd(row_addr, high_row_data);

    // =========================================================
    // Output select
    // =========================================================

    always @(*) begin
        if (init_mode) begin
            // Same init command to all three MAX7219 modules.
            tx_data = {init_cmd, init_cmd, init_cmd};
        end
        else begin
            // Daisy chain order:
            // 3rd module = High
            // 2nd module = Mid
            // 1st module = Low
            tx_data = {high_cmd, mid_cmd, low_cmd};
        end
    end

endmodule