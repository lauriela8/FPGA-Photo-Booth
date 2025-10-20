`timescale 1ns/1ps

module Sobel_Filter_tb;

    // -------------------------------------------------
    // 작은 해상도 (8x8)로 테스트
    // -------------------------------------------------
    localparam int IMG_W = 8;
    localparam int IMG_H = 8;

    logic        clk, reset;
    logic        we_in;
    logic [16:0] wAddr_in;
    logic [15:0] wData_in;

    logic        we_out;
    logic [16:0] wAddr_out;
    logic [15:0] wData_out;

    // DUT
    Sobel_Filter #(
        .IMG_WIDTH (IMG_W),
        .IMG_HEIGHT(IMG_H),
        .THRESHOLD (15)
    ) dut (
        .clk      (clk),
        .reset    (reset),
        .we_in    (we_in),
        .wAddr_in (wAddr_in),
        .wData_in (wData_in),
        .we_out   (we_out),
        .wAddr_out(wAddr_out),
        .wData_out(wData_out)
    );

    // -------------------------------------------------
    // 클록 생성
    // -------------------------------------------------
    always #5 clk = ~clk;

    // -------------------------------------------------
    // 테스트 입력 패턴: 그레이디언트
    // R 채널 = row+col, G 채널 = row*2, B 채널 = col*3
    // -------------------------------------------------
    initial begin
        clk   = 0;
        reset = 1;
        we_in = 0;
        wAddr_in = 0;
        wData_in = 0;

        repeat (5) @(posedge clk);
        reset = 0;

        for (int row = 0; row < IMG_H; row++) begin
            for (int col = 0; col < IMG_W; col++) begin
                @(posedge clk);
                we_in    <= 1;
                wAddr_in <= row * IMG_W + col;

                // RGB565 입력 (R5,G6,B5)
                wData_in[15:11] <= (row+col) % 32;   // R
                wData_in[10:5]  <= (row*2) % 64;     // G
                wData_in[4:0]   <= (col*3) % 32;     // B
            end
        end

        @(posedge clk);
        we_in <= 0;

        repeat (30) @(posedge clk);
        $finish;
    end

    // -------------------------------------------------
    // VCD 덤프 + 출력 모니터링
    // -------------------------------------------------
    initial begin
        $dumpfile("Sobel_Filter_tb.vcd");
        $dumpvars(0, Sobel_Filter_tb);

        // 내부 신호도 보고 싶다면 추가
        $dumpvars(0, dut.p00, dut.p01, dut.p02,
                      dut.p10, dut.p11, dut.p12,
                      dut.p20, dut.p21, dut.p22,
                      dut.gx, dut.gy, dut.mag);

        $display("time\taddr_in\tdata_in\taddr_out\tdata_out");
        forever begin
            @(posedge clk);
            if (we_out) begin
                $display("%0t\t%0d\t%h\t%0d\t%h",
                         $time, wAddr_in, wData_in,
                         wAddr_out, wData_out);
            end
        end
    end

endmodule
