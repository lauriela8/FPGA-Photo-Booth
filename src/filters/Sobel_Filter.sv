`timescale 1ns / 1ps

module Sobel_Filter #(
    parameter IMG_WIDTH  = 320,
    parameter IMG_HEIGHT = 240,
    parameter THRESHOLD  = 15
) (
    input  logic        clk,
    input  logic        reset,
    // from MemController
    input  logic        we_in,
    input  logic [16:0] wAddr_in,
    input  logic [15:0] wData_in,
    // to frame_buffer
    output logic        we_out,
    output logic [16:0] wAddr_out,
    output logic [15:0] wData_out
);

    // ============================================================
    // RGB565 → Gray (8비트)
    // ============================================================
    logic [7:0] in_r, in_g, in_b;
    logic [7:0] gray;

    assign in_r = {wData_in[15:11], 3'b0};
    assign in_g = {wData_in[10:5], 2'b0};
    assign in_b = {wData_in[4:0], 3'b0};

    always_ff @(posedge clk) begin
        if (reset) gray <= 0;
        else if (we_in)
            gray <= ((in_r * 16'd77) + (in_g * 16'd150) + (in_b * 16'd29)) >> 8;
    end

    // ============================================================
    // 라인버퍼 (이전 2줄) + 3x3 윈도우
    // ============================================================
    logic [7:0] line1[0:IMG_WIDTH-1];
    logic [7:0] line2[0:IMG_WIDTH-1];

    logic [7:0] p00, p01, p02, p10, p11, p12, p20, p21, p22;
    logic [$clog2(IMG_WIDTH)-1:0] col_cnt, col_d1, col_d2, col_d3;
    logic [$clog2(IMG_HEIGHT)-1:0] row_cnt, row_d1, row_d2, row_d3;

    logic [16:0] addr_d1, addr_d2, addr_d3;
    logic we_d1, we_d2, we_d3;

    wire frame_start = we_in && (wAddr_in == 17'd0);

    always_ff @(posedge clk) begin
        if (reset || frame_start) begin
            col_cnt <= 0;
            row_cnt <= 0;
            {p00, p01, p02, p10, p11, p12, p20, p21, p22} <= '{default: 0};
            addr_d1 <= 0;
            addr_d2 <= 0;
            addr_d3 <= 0;
            we_d1 <= 0;
            we_d2 <= 0;
            we_d3 <= 0;
            col_d1 <= 0;
            col_d2 <= 0;
            col_d3 <= 0;
            row_d1 <= 0;
            row_d2 <= 0;
            row_d3 <= 0;
            for (int i = 0; i < IMG_WIDTH; i++) begin
                line1[i] <= 0;
                line2[i] <= 0;
            end
        end else if (we_in) begin
            addr_d1 <= wAddr_in;
            addr_d2 <= addr_d1;
            addr_d3 <= addr_d2;
            we_d1   <= we_in;
            we_d2   <= we_d1;
            we_d3   <= we_d2;

            if (col_cnt == IMG_WIDTH - 1) begin
                col_cnt <= 0;
                if (row_cnt == IMG_HEIGHT - 1) row_cnt <= 0;
                else row_cnt <= row_cnt + 1;
            end else col_cnt <= col_cnt + 1;

            col_d1 <= col_cnt;
            col_d2 <= col_d1;
            col_d3 <= col_d2;
            row_d1 <= row_cnt;
            row_d2 <= row_d1;
            row_d3 <= row_d2;

            p00 <= p01;
            p01 <= p02;
            p02 <= line2[col_cnt];
            p10 <= p11;
            p11 <= p12;
            p12 <= line1[col_cnt];
            p20 <= p21;
            p21 <= p22;
            p22 <= gray;

            line2[col_cnt] <= line1[col_cnt];
            line1[col_cnt] <= gray;
        end
    end

    // ============================================================
    // Sobel 연산
    // ============================================================
    logic signed [11:0] gx, gy;
    logic [12:0] mag;
    logic [7:0] sobel_val, edge_bin;

    always_ff @(posedge clk) begin
        if (reset) begin
            gx <= 0;
            gy <= 0;
            mag <= 0;
            sobel_val <= 0;
            edge_bin <= 0;
        end else if (we_in) begin
            gx <= (p02 + (p12 << 1) + p22) - (p00 + (p10 << 1) + p20);
            gy <= (p20 + (p21 << 1) + p22) - (p00 + (p01 << 1) + p02);
            mag <= (gx[11] ? -gx : gx) + (gy[11] ? -gy : gy);

            sobel_val <= (mag >> 3 > 8'hFF) ? 8'hFF : mag[10:3];
            edge_bin <= (sobel_val >= THRESHOLD) ? 8'hFF : 8'h00;
        end
    end

    // ============================================================
    // edge_bin 파이프라인 → 데이터도 d3 단계로 맞추기
    // ============================================================
    logic [7:0] edge_d1, edge_d2, edge_d3;

    always_ff @(posedge clk) begin
        if (reset) begin
            edge_d1 <= 0;
            edge_d2 <= 0;
            edge_d3 <= 0;
        end else begin
            if (we_in) edge_d1 <= edge_bin;
            if (we_d1) edge_d2 <= edge_d1;
            if (we_d2) edge_d3 <= edge_d2;
        end
    end

    // ============================================================
    // 출력 (RGB565) — addr/we/데이터 모두 d3에서 일치
    // ============================================================
    wire at_border_d3 = (row_d3 < 2) || (col_d3 < 2) ||
                        (row_d3 >= IMG_HEIGHT-2) || (col_d3 >= IMG_WIDTH-2);

    logic [15:0] dout_reg;
    always_ff @(posedge clk) begin
        if (reset) dout_reg <= 16'h0000;
        else if (we_d3) begin
            dout_reg <= {edge_d3[7:3], edge_d3[7:2], edge_d3[7:3]};
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            wAddr_out <= 0;
            we_out    <= 0;
        end else begin
            wAddr_out <= addr_d3;
            we_out    <= we_d3;
        end
    end

    assign wData_out = at_border_d3 ? 16'h0000 : dout_reg;

endmodule
