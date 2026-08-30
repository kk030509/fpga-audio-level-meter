`timescale 1ns / 1ps

module tb_audio_sample_reader;

    reg clk;
    reg reset;
    reg sample_req;

    wire [7:0] sample_out;
    wire       sample_valid;

    audio_sample_reader #(
        .DEPTH   (4),
        .MEMFILE ("test_audio.mem")
    ) dut (
        .clk          (clk),
        .reset        (reset),
        .sample_req   (sample_req),
        .sample_out   (sample_out),
        .sample_valid (sample_valid)
    );

    // 100 MHz clock
    // 1주기 = 10 ns
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin

        reset      = 1;
        sample_req = 0;

        #20;
        reset = 0;

        // 첫 번째 PCM 요청
        #10;
        sample_req = 1;

        #10;
        sample_req = 0;

        #30;

        // 두 번째 PCM 요청
        sample_req = 1;

        #10;
        sample_req = 0;

        #30;

        // 세 번째 PCM 요청
        sample_req = 1;

        #10;
        sample_req = 0;

        #50;

        $finish;
    end

endmodule
