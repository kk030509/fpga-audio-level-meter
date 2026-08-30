module i2s_transmitter #(
    parameter integer DATA_WIDTH    = 16,
    parameter integer BCLK_HALF_DIV = 195
)(
    input  wire                         clk,
    input  wire                         reset,

    input  wire signed [DATA_WIDTH-1:0] sample_in,
    output reg                          sample_req,

    output reg                          i2s_bck,
    output reg                          i2s_lrck,
    output reg                          i2s_dout
);

    //-------------------------------------------------
    // Parameter
    //-------------------------------------------------
    localparam integer FRAME_BITS = DATA_WIDTH * 2;
    localparam integer DIV_WIDTH  = $clog2(BCLK_HALF_DIV);

    //-------------------------------------------------
    // Register
    //-------------------------------------------------
    reg [DIV_WIDTH-1:0] div_cnt;

    reg [$clog2(FRAME_BITS)-1:0] bit_cnt;

    // 원본 PCM 보관
    reg signed [DATA_WIDTH-1:0] sample_reg;

    // 실제 직렬 전송용
    reg [DATA_WIDTH-1:0] shift_reg;


    //-------------------------------------------------
    // BCK Falling Edge 검출
    //-------------------------------------------------
    wire bck_fall;

    assign bck_fall =
        (div_cnt == BCLK_HALF_DIV - 1) &&
        (i2s_bck == 1'b1);


    //-------------------------------------------------
    // BCK 생성
    //-------------------------------------------------
    always @(posedge clk or posedge reset) begin

        if (reset) begin
            div_cnt <= 0;
            i2s_bck <= 0;
        end

        else if (div_cnt == BCLK_HALF_DIV - 1) begin
            div_cnt <= 0;
            i2s_bck <= ~i2s_bck;
        end

        else begin
            div_cnt <= div_cnt + 1'b1;
        end

    end


    //-------------------------------------------------
    // I2S Data 전송
    //-------------------------------------------------
    always @(posedge clk or posedge reset) begin

        if (reset) begin
            bit_cnt      <= 0;

            sample_reg   <= 0;
            shift_reg    <= 0;

            sample_req   <= 0;

            i2s_lrck     <= 0;     // Left
            i2s_dout     <= 0;
        end

        else begin

            // 기본값 0
            // 필요한 순간에만 1이 되는 1-clock pulse
            sample_req <= 1'b0;


            //-------------------------------------------------
            // BCK Falling Edge에서 DATA 변경
            //-------------------------------------------------
            if (bck_fall) begin

                //-------------------------------------------------
                // 다음 PCM 미리 요청
                //-------------------------------------------------
                if (bit_cnt == FRAME_BITS - 2) begin
                    sample_req <= 1'b1;
                end


                //-------------------------------------------------
                // Left Channel 시작
                //-------------------------------------------------
                if (bit_cnt == 0) begin

                    // 새로운 PCM 저장
                    sample_reg <= sample_in;

                    // Left 전송용 데이터 Load
                    shift_reg <= sample_in;

                    // 첫 번째 MSB는 직접 출력
                    i2s_dout <= sample_in[DATA_WIDTH-1];
                end


                //-------------------------------------------------
                // Right Channel 시작
                //-------------------------------------------------
                else if (bit_cnt == DATA_WIDTH) begin

                    // Left에서 사용했던 원본 PCM 다시 Load
                    shift_reg <= sample_reg;

                    // Right MSB 출력
                    i2s_dout <= sample_reg[DATA_WIDTH-1];
                end


                //-------------------------------------------------
                // 일반 Bit 전송
                //-------------------------------------------------
                else begin

                    // 한 Bit 왼쪽 Shift
                    shift_reg <= {
                        shift_reg[DATA_WIDTH-2:0],
                        1'b0
                    };

                    // 다음 Bit 출력
                    i2s_dout <= shift_reg[DATA_WIDTH-2];

                end


                //-------------------------------------------------
                // Standard I2S LRCK Timing
                //-------------------------------------------------

                // Left LSB 출력 시점에
                // LRCK를 미리 Right로 변경
                if (bit_cnt == DATA_WIDTH - 1) begin
                    i2s_lrck <= 1'b1;
                end

                // Right LSB 출력 시점에
                // LRCK를 미리 Left로 변경
                else if (bit_cnt == FRAME_BITS - 1) begin
                    i2s_lrck <= 1'b0;
                end


                //-------------------------------------------------
                // Bit Counter
                //-------------------------------------------------
                if (bit_cnt == FRAME_BITS - 1)
                    bit_cnt <= 0;
                else
                    bit_cnt <= bit_cnt + 1'b1;

            end
        end
    end

endmodule
