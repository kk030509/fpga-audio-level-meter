module band_level_mapper (
    input wire clk,
    input wire reset,

    input wire [15:0] low_avg,
    input wire [15:0] mid_avg,
    input wire [15:0] high_avg,
    input wire        avg_valid,

    output reg [3:0] low_level,
    output reg [3:0] mid_level,
    output reg [3:0] high_level,
    output reg       level_valid
);

    function [3:0] low_to_level;
        input [15:0] value;
        begin
            if      (value >= 16'd368) low_to_level = 4'd8;
            else if (value >= 16'd320) low_to_level = 4'd7;
            else if (value >= 16'd272) low_to_level = 4'd6;
            else if (value >= 16'd224) low_to_level = 4'd5;
            else if (value >= 16'd192) low_to_level = 4'd4;
            else if (value >= 16'd144) low_to_level = 4'd3;
            else if (value >= 16'd96)  low_to_level = 4'd2;
            else if (value >= 16'd48)  low_to_level = 4'd1;
            else                       low_to_level = 4'd0;
        end
    endfunction

    function [3:0] mid_to_level;
        input [15:0] value;
        begin
            if      (value >= 16'd160) mid_to_level = 4'd8;
            else if (value >= 16'd144) mid_to_level = 4'd7;
            else if (value >= 16'd112) mid_to_level = 4'd6;
            else if (value >= 16'd96)  mid_to_level = 4'd5;
            else if (value >= 16'd80)  mid_to_level = 4'd4;
            else if (value >= 16'd64)  mid_to_level = 4'd3;
            else if (value >= 16'd32)  mid_to_level = 4'd2;
            else if (value >= 16'd16)  mid_to_level = 4'd1;
            else                       mid_to_level = 4'd0;
        end
    endfunction

    function [3:0] high_to_level;
        input [15:0] value;
        begin
            if      (value >= 16'd128) high_to_level = 4'd8;
            else if (value >= 16'd112) high_to_level = 4'd7;
            else if (value >= 16'd96)  high_to_level = 4'd6;
            else if (value >= 16'd80)  high_to_level = 4'd5;
            else if (value >= 16'd64)  high_to_level = 4'd4;
            else if (value >= 16'd48)  high_to_level = 4'd3;
            else if (value >= 16'd32)  high_to_level = 4'd2;
            else if (value >= 16'd16)  high_to_level = 4'd1;
            else                       high_to_level = 4'd0;
        end
    endfunction

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            low_level   <= 4'd0;
            mid_level   <= 4'd0;
            high_level  <= 4'd0;
            level_valid <= 1'b0;
        end
        else begin
            level_valid <= 1'b0;

            if (avg_valid) begin
                low_level   <= low_to_level(low_avg);
                mid_level   <= mid_to_level(mid_avg);
                high_level  <= high_to_level(high_avg);
                level_valid <= 1'b1;
            end
        end
    end

endmodule
