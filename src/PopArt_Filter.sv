`timescale 1ns / 1ps

module PopArt_Filter #(  // Strong posterization + vivid color boost + edge overlay
    parameter int IMG_WIDTH    = 320,
    parameter int IMG_HEIGHT   = 240,
    // Posterization level (keep MSBs)
    parameter int KEEP_RB_MSBS = 2,
    parameter int KEEP_G_MSBS  = 2,
    // Edge threshold (|Gx|+|Gy|)
    parameter int EDGE_THR     = 50
) (
    input logic        clk,
    input logic        reset,
    // camera write stream
    input logic        we_in,
    input logic [16:0] wAddr_in,
    input logic [15:0] wData_in,

    // to frame buffer
    output logic        we_out,
    output logic [16:0] wAddr_out,
    output logic [15:0] wData_out
);

    // ---------------------------------------------------------
    // 1) 좌표 카운터
    // ---------------------------------------------------------
    logic [$clog2(IMG_WIDTH )-1:0] col_cnt;
    logic [$clog2(IMG_HEIGHT)-1:0] row_cnt;
    wire frame_start = (we_in && (wAddr_in == 17'd0));

    always_ff @(posedge clk) begin
        if (reset) begin
            col_cnt <= '0;
            row_cnt <= '0;
        end else if (we_in) begin
            if (frame_start) begin
                col_cnt <= '0;
                row_cnt <= '0;
            end else if (col_cnt == IMG_WIDTH - 1) begin
                col_cnt <= '0;
                row_cnt <= (row_cnt == IMG_HEIGHT - 1) ? '0 : (row_cnt + 1'b1);
            end else begin
                col_cnt <= col_cnt + 1'b1;
            end
        end
    end

    // ---------------------------------------------------------
    // 2) RGB565 분리
    // ---------------------------------------------------------
    logic [4:0] in_r5;
    logic [5:0] in_g6;
    logic [4:0] in_b5;
    always_comb begin
        in_r5 = wData_in[15:11];
        in_g6 = wData_in[10:5];
        in_b5 = wData_in[4:0];
    end

    // ---------------------------------------------------------
    // 3) Posterization (원색 강조)
    // ---------------------------------------------------------
    // MSB만 남기고 나머지는 0으로 → 색상 영역이 확 줄어들면서 팝아트 느낌
    wire [4:0] post_r5;
    wire [5:0] post_g6;
    wire [4:0] post_b5;

    assign post_r5 = {in_r5[4:3], 3'b000};  // 2 MSB만 유지
    assign post_g6 = {in_g6[5:4], 4'b0000};  // 2 MSB만 유지
    assign post_b5 = {in_b5[4:3], 3'b000};  // 2 MSB만 유지

    // ---------------------------------------------------------
    // 4) Color boost (채도 극대화)
    // ---------------------------------------------------------
    // 간단히 MSB를 더 키워 원색을 강조
    logic [4:0] boost_r5;
    logic [5:0] boost_g6;
    logic [4:0] boost_b5;

    always_comb begin
        boost_r5 = (post_r5 << 1 > 5'd31) ? 5'd31 : (post_r5 << 1);
        boost_g6 = (post_g6 << 1 > 6'd63) ? 6'd63 : (post_g6 << 1);
        boost_b5 = (post_b5 << 1 > 5'd31) ? 5'd31 : (post_b5 << 1);
    end

    // ---------------------------------------------------------
    // 5) Sobel edge (윤곽선 강조)
    // ---------------------------------------------------------
    // 간단히 G 채널만 사용
    logic signed [7:0] gx, gy;
    logic [7:0] abs_gx, abs_gy;
    logic [8:0] edge_mag;

    always_ff @(posedge clk) begin
        if (reset) begin
            gx <= '0;
            gy <= '0;
            abs_gx <= '0;
            abs_gy <= '0;
            edge_mag <= '0;
        end else if (we_in) begin
            gx <= $signed(
                in_g6
            ) - $signed(
                in_r5
            );  // 간단 차분 (실제는 3x3 윈도우 Sobel 가능)
            gy <= $signed(in_g6) - $signed(in_b5);

            abs_gx <= gx[7] ? (~gx + 8'd1) : gx;
            abs_gy <= gy[7] ? (~gy + 8'd1) : gy;
            edge_mag <= abs_gx + abs_gy;
        end
    end

    // ---------------------------------------------------------
    // 6) 출력: 엣지 → 블랙, 나머지 → 원색 강조
    // ---------------------------------------------------------
    logic [4:0] out_r5;
    logic [5:0] out_g6;
    logic [4:0] out_b5;

    always_ff @(posedge clk) begin
        if (reset) begin
            out_r5 <= '0;
            out_g6 <= '0;
            out_b5 <= '0;
        end else if (we_in) begin
            if (edge_mag > EDGE_THR) begin
                // Edge는 블랙 (윤곽선만 살림)
                out_r5 <= 5'd0;
                out_g6 <= 6'd0;
                out_b5 <= 5'd0;
            end else begin
                // 배경은 흰색 기반으로, 원색 강조값을 섞음
                // 흰색: R=31, G=63, B=31
                out_r5 <= (boost_r5 > 5'd0) ? boost_r5 : 5'd31;
                out_g6 <= (boost_g6 > 6'd0) ? boost_g6 : 6'd63;
                out_b5 <= (boost_b5 > 5'd0) ? boost_b5 : 5'd31;
            end
        end
    end

    assign wData_out = {out_r5, out_g6, out_b5};

    // ---------------------------------------------------------
    // 7) Output timing
    // ---------------------------------------------------------
    always_ff @(posedge clk) begin
        if (reset) begin
            wAddr_out <= '0;
            we_out <= 1'b0;
        end else if (we_in) begin
            wAddr_out <= wAddr_in;
            we_out    <= we_in;
        end
    end
endmodule
