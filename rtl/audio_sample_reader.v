module audio_sample_reader #(
    parameter integer DEPTH = 64000,
    parameter MEMFILE = "audio_8k_s8.mem"
)(
    input  wire clk,
    input  wire reset,

    input  wire       sample_req, //I2S에서 오는 신호, pcm샘플 하나 읽어줘
    output reg  [7:0] sample_out, //rom에서 읽은 실제 8bit pcm샘플 하나
    output reg        sample_valid
);
    localparam integer ADDR_WIDTH = $clog2(DEPTH);
    reg [ADDR_WIDTH-1:0] addr; //rom 주소
    reg                  rom_en_d; // 한 클럭 지연시킨 rom_read 요청
    wire [7:0] rom_dout; //dout이랑 연결되는 선
	
	    audio_rom #(
        .DEPTH      (DEPTH),
        .MEMFILE    (MEMFILE)
    ) u_audio_rom (
        .clk  (clk),
        .en   (sample_req),
        .addr (addr),
        .dout (rom_dout)
    );
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            addr         <= 0;
            rom_en_d     <= 1'b0;

            sample_out   <= 8'd0;
            sample_valid <= 1'b0;
        end
        else begin
            sample_valid <= 1'b0;

            // Delay sample_req by one clock to align with ROM output.
            rom_en_d <= sample_req;

            if (sample_req) begin
                if (addr == DEPTH - 1) begin
                    addr <= 0;
                end
                else begin
                    addr <= addr + 1'b1;
                end
            end

            if (rom_en_d) begin
                sample_out   <= rom_dout;
                sample_valid <= 1'b1;
            end
        end
    end

endmodule
