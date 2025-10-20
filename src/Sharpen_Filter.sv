`timescale 1ns / 1ps

module Sharpen_Filter #(
    parameter int IMG_WIDTH  = 320,
    parameter int IMG_HEIGHT = 240
) (
    input  logic        clk,
    input  logic        reset,
    // from OV7670_MemController
    input  logic        we_in,
    input  logic [16:0] wAddr_in,
    input  logic [15:0] wData_in,
    // to frame_buffer
    output logic        we_out,
    output logic [16:0] wAddr_out,
    output logic [15:0] wData_out
);

    // =========================================================
    // 좌표 카운터 
    // =========================================================
    logic [$clog2(IMG_WIDTH)-1:0] col_cnt;
    logic [$clog2(IMG_HEIGHT)-1:0] row_cnt;

    wire frame_start = (we_in && (wAddr_in == 17'd0));

    always_ff @(posedge clk) begin
        if (reset) begin
            col_cnt <= '0;
            row_cnt <= '0;
        end else if (we_in) begin
            if (col_cnt == IMG_WIDTH - 1) begin
                col_cnt <= '0;
                if (row_cnt == IMG_HEIGHT - 1) row_cnt <= '0;
                else row_cnt <= row_cnt + 1'b1;
            end else begin
                col_cnt <= col_cnt + 1'b1;
            end
            if (frame_start) begin
                col_cnt <= '0;
                row_cnt <= '0;
            end
        end
    end

    // =========================================================
    // 입력 픽셀 RGB565 분리
    // =========================================================
    logic [4:0] in_r5;
    logic [5:0] in_g6;
    logic [4:0] in_b5;

    always_comb begin
        in_r5 = wData_in[15:11];
        in_g6 = wData_in[10:5];
        in_b5 = wData_in[4:0];
    end

    // =========================================================
    // 라인버퍼(이전 2줄) + 3x3 윈도우 시프트
    // =========================================================
    logic [4:0] line1_r[0:IMG_WIDTH-1], line2_r[0:IMG_WIDTH-1];
    logic [5:0] line1_g[0:IMG_WIDTH-1], line2_g[0:IMG_WIDTH-1];
    logic [4:0] line1_b[0:IMG_WIDTH-1], line2_b[0:IMG_WIDTH-1];

    logic [4:0] r00, r01, r02, r10, r11, r12, r20, r21, r22;
    logic [5:0] g00, g01, g02, g10, g11, g12, g20, g21, g22;
    logic [4:0] b00, b01, b02, b10, b11, b12, b20, b21, b22;

    logic [15:0] raw_pixel_d1, raw_pixel_d2;
    logic [16:0] addr_d1, addr_d2, addr_d3;
    logic we_d1, we_d2, we_d3;

    always_ff @(posedge clk) begin
        if (reset) begin
            {r00, r01, r02, r10, r11, r12, r20, r21, r22} <= '{default: '0};
            {g00, g01, g02, g10, g11, g12, g20, g21, g22} <= '{default: '0};
            {b00, b01, b02, b10, b11, b12, b20, b21, b22} <= '{default: '0};
            raw_pixel_d1                                  <= '0;
            raw_pixel_d2                                  <= '0;
            addr_d1                                       <= '0;
            addr_d2                                       <= '0;
            we_d1                                         <= 1'b0;
            we_d2                                         <= 1'b0;
        end else begin
            raw_pixel_d1 <= wData_in;
            raw_pixel_d2 <= raw_pixel_d1;
            addr_d1      <= wAddr_in;
            addr_d2      <= addr_d1;
            addr_d3      <= addr_d2;
            we_d1        <= we_in;
            we_d2        <= we_d1;
            we_d3        <= we_d2;

            if (we_in) begin
                r00 <= r01;
                r01 <= r02;
                r02 <= line2_r[col_cnt];
                r10 <= r11;
                r11 <= r12;
                r12 <= line1_r[col_cnt];
                r20 <= r21;
                r21 <= r22;
                r22 <= in_r5;

                g00 <= g01;
                g01 <= g02;
                g02 <= line2_g[col_cnt];
                g10 <= g11;
                g11 <= g12;
                g12 <= line1_g[col_cnt];
                g20 <= g21;
                g21 <= g22;
                g22 <= in_g6;

                b00 <= b01;
                b01 <= b02;
                b02 <= line2_b[col_cnt];
                b10 <= b11;
                b11 <= b12;
                b12 <= line1_b[col_cnt];
                b20 <= b21;
                b21 <= b22;
                b22 <= in_b5;

                line2_r[col_cnt] <= line1_r[col_cnt];
                line1_r[col_cnt] <= in_r5;
                line2_g[col_cnt] <= line1_g[col_cnt];
                line1_g[col_cnt] <= in_g6;
                line2_b[col_cnt] <= line1_b[col_cnt];
                line1_b[col_cnt] <= in_b5;
            end
        end
    end

    // =========================================================
    // 샤프닝 컨볼루션 (센터*5 - 상하좌우)
    // =========================================================
    logic signed [9:0] conv_r, conv_g, conv_b;

    always_ff @(posedge clk) begin
        if (reset) begin
            conv_r <= '0;
            conv_g <= '0;
            conv_b <= '0;
        end else begin
            conv_r <= ($signed(
                {1'b0, r11}
            ) * 10'sd5) - ($signed(
                {1'b0, r01}
            ) + $signed(
                {1'b0, r10}
            ) + $signed(
                {1'b0, r12}
            ) + $signed(
                {1'b0, r21}
            ));

            conv_g <= ($signed(
                {1'b0, g11}
            ) * 10'sd5) - ($signed(
                {1'b0, g01}
            ) + $signed(
                {1'b0, g10}
            ) + $signed(
                {1'b0, g12}
            ) + $signed(
                {1'b0, g21}
            ));

            conv_b <= ($signed(
                {1'b0, b11}
            ) * 10'sd5) - ($signed(
                {1'b0, b01}
            ) + $signed(
                {1'b0, b10}
            ) + $signed(
                {1'b0, b12}
            ) + $signed(
                {1'b0, b21}
            ));
        end
    end

    // =========================================================
    // 에지 처리 & 포화 클리핑 & 출력 정렬
    //  - 에지(앞 2행/2열)는 원본 패스-스루
    //  - 내부 픽셀은 샤프닝 결과 사용
    //  - 파이프 지연: conv가 1스테이지 → 주소/WE를 2스테이지 맞춤(raw_pixel_d2, addr_d2, we_d2)
    // =========================================================
    logic [4:0] sharp_r5;
    logic [5:0] sharp_g6;
    logic [4:0] sharp_b5;

    wire at_border = (col_cnt==0) || (row_cnt==0) ||
                 (col_cnt==IMG_WIDTH-1) || (row_cnt==IMG_HEIGHT-1);

    always_ff @(posedge clk) begin
        if (reset) begin
            sharp_r5 <= 0;
            sharp_g6 <= 0;
            sharp_b5 <= 0;
        end else if (at_border) begin
            sharp_r5 <= raw_pixel_d2[15:11];
            sharp_g6 <= raw_pixel_d2[10:5];
            sharp_b5 <= raw_pixel_d2[4:0];
        end else begin
            sharp_r5 <= (conv_r < 0) ? 0 : (conv_r > 31) ? 31 : conv_r[4:0];
            sharp_g6 <= (conv_g < 0) ? 0 : (conv_g > 63) ? 63 : conv_g[5:0];
            sharp_b5 <= (conv_b < 0) ? 0 : (conv_b > 31) ? 31 : conv_b[4:0];
        end
    end

    assign wData_out = {sharp_r5, sharp_g6, sharp_b5};

    always_ff @(posedge clk) begin
        if (reset) begin
            wAddr_out <= '0;
            we_out <= 1'b0;
        end else begin
            wAddr_out <= addr_d3;
            we_out <= we_d3;
        end
    end

endmodule
