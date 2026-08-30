module audio_rom #(
    parameter integer DEPTH = 64000,
    parameter MEMFILE = "audio_8k_s8.mem"
)(
    input  wire                      clk,
    input  wire                      en,
    input  wire [$clog2(DEPTH)-1:0]  addr,//주소 폭, 2^16이면 64000개 표현 가능
    output reg  [7:0]                dout
);

    (* rom_style = "block" *)   // 가능하면 Block RAM으로 구현
    reg [7:0] mem [0:DEPTH-1]; // 8-bit PCM sample을 DEPTH개 저장

    initial begin
        $readmemh(MEMFILE, mem); // Hex 값을 읽어 mem 배열 초기화
    end

    always @(posedge clk) begin
        if (en)
            dout <= mem[addr];
    end

endmodule
