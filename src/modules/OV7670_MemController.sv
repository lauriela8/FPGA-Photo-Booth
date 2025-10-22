`timescale 1ns / 1ps

module OV7670_MemController #(
    parameter int IMG_W = 320,
    parameter int IMG_H = 240
) (
    input  logic        clk,
    input  logic        reset,
    // OV7670 side
    input  logic        href,
    input  logic        vsync,
    input  logic [ 7:0] ov7670_data,
    // memory side
    output logic        we,
    output logic [16:0] wAddr,
    output logic [15:0] wData
);
    // 내부 카운터
    logic [ 9:0] h_counter;  // 0..639 (짝수/홀수 byte)
    logic [ 7:0] v_counter;  // 0..239
    logic [15:0] pixel_data;

    // 주소 계산
    wire  [16:0] addr_next = v_counter * IMG_W + h_counter[9:1];

    // 파이프라인용 레지스터
    logic        we_d;
    logic [16:0] wAddr_d;
    logic [15:0] wData_d;

    // ------------------------------
    // 가로 카운터 & 픽셀 조립
    // ------------------------------
    always_ff @(posedge clk, posedge reset) begin
        if (reset) begin
            h_counter  <= 0;
            pixel_data <= 0;
            we_d       <= 0;
        end else begin
            if (href) begin
                h_counter <= h_counter + 1;

                if (h_counter[0] == 0) begin
                    // 짝수 byte = MSB 먼저 (기본)
                    pixel_data[15:8] <= ov7670_data;
                    we_d             <= 1'b0;  // 아직 픽셀 미완성
                end else begin
                    // 홀수 byte = LSB, 픽셀 완성됨
                    pixel_data[7:0] <= ov7670_data;

                    wAddr_d         <= addr_next;  // 현재 픽셀 주소
                    wData_d         <= {pixel_data[15:8], ov7670_data};
                    we_d            <= 1'b1;  // write enable
                end
            end else begin
                h_counter <= 0;
                we_d      <= 1'b0;
            end
        end
    end

    // ------------------------------
    // 세로 카운터
    // ------------------------------
    always_ff @(posedge clk, posedge reset) begin
        if (reset) begin
            v_counter <= 0;
        end else begin
            if (vsync) begin
                v_counter <= 0;  // 프레임 시작
            end else begin
                if (h_counter == (IMG_W * 2 - 1)) begin
                    v_counter <= v_counter + 1;
                end
            end
        end
    end

    // ------------------------------
    // 출력 파이프라인 (정렬)
    // ------------------------------
    always_ff @(posedge clk, posedge reset) begin
        if (reset) begin
            we    <= 1'b0;
            wAddr <= 0;
            wData <= 0;
        end else begin
            we    <= we_d;
            wAddr <= wAddr_d;
            wData <= wData_d;
        end
    end

endmodule
