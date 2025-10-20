`timescale 1ns / 1ps

module Sharpen_Filter_tb;

    // -------------------------------------------------
    // 작은 해상도 (8x8)로 테스트 → 라인버퍼 동작 보기 쉽게
    // -------------------------------------------------
    localparam int IMG_W = 8;
    localparam int IMG_H = 8;

    logic clk, reset;
    logic        we_in;
    logic [16:0] wAddr_in;
    logic [15:0] wData_in;

    logic        we_out;
    logic [16:0] wAddr_out;
    logic [15:0] wData_out;

    // DUT
    Sharpen_Filter #(
        .IMG_WIDTH (IMG_W),
        .IMG_HEIGHT(IMG_H)
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
    // 입력 이미지: 단순 패턴
    // R = (row+col), G = (row*2+col), B = (row*3+col)
    // -------------------------------------------------
    initial begin
        clk = 0;
        reset = 1;
        we_in = 0;
        wAddr_in = 0;
        wData_in = 0;

        repeat (5) @(posedge clk);
        reset = 0;

        // 픽셀 스트리밍 입력
        for (int row = 0; row < IMG_H; row++) begin
            for (int col = 0; col < IMG_W; col++) begin
                @(posedge clk);
                we_in    <= 1;
                wAddr_in <= row * IMG_W + col;

                wData_in[15:11] <= (row+col) % 32;  // R5
                wData_in[10:5]  <= (row*2+col) % 64; // G6
                wData_in[4:0]   <= (row*3+col) % 32; // B5
            end
        end

        // 입력 종료
        @(posedge clk);
        we_in <= 0;

        // 파이프라인 플러시
        repeat (30) @(posedge clk);
        $finish;
    end

    // -------------------------------------------------
    // VCD 덤프 + 출력 로그
    // 내부 라인버퍼 윈도우(r00~r22 등)까지 캡쳐
    // -------------------------------------------------
    initial begin
        $dumpfile("Sharpen_Filter_tb.vcd");
        $dumpvars(0, Sharpen_Filter_tb);
        // 내부 윈도우 관찰 (라인버퍼 값 이동 확인용)
        $dumpvars(0, dut.r00, dut.r01, dut.r02, dut.r10, dut.r11, dut.r12,
                  dut.r20, dut.r21, dut.r22);

        $display("time\taddr_in\tdata_in\t\taddr_out\tdata_out");
        forever begin
            @(posedge clk);
            if (we_out) begin
                $display("%0t\t%0d\t%h\t%0d\t%h", $time, wAddr_in, wData_in,
                         wAddr_out, wData_out);
            end
        end
    end

endmodule
