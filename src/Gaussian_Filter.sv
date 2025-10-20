`timescale 1ns / 1ps

module Gaussian_Filter #(
    parameter int IMG_WIDTH  = 320,
    parameter int IMG_HEIGHT = 240
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        we_in,
    input  logic [16:0] wAddr_in,
    input  logic [15:0] wData_in,
    output logic        we_out,
    output logic [16:0] wAddr_out,
    output logic [15:0] wData_out
);
    localparam int AW = $clog2(IMG_WIDTH);
    localparam int AH = $clog2(IMG_HEIGHT);

    logic [AW-1:0] x;
    logic [AH-1:0] y;

    always_comb begin
        x = wAddr_in % IMG_WIDTH;
        y = wAddr_in / IMG_WIDTH;
    end

    logic [15:0] line_even[0:IMG_WIDTH-1];
    logic [15:0] line_odd [0:IMG_WIDTH-1];

    logic [15:0] top_tap_0, top_tap_1, top_tap_2;
    logic [15:0] mid_tap_0, mid_tap_1, mid_tap_2;
    logic [15:0] cur_tap_0, cur_tap_1, cur_tap_2;

    logic [15:0] top_rd, mid_rd;

    function automatic logic [4:0] R5(input logic [15:0] p);
        return p[15:11];
    endfunction
    function automatic logic [5:0] G6(input logic [15:0] p);
        return p[10:5];
    endfunction
    function automatic logic [4:0] B5(input logic [15:0] p);
        return p[4:0];
    endfunction

    logic win_valid;
    assign win_valid = (x >= 2) && (y >= 2);

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            top_tap_0 <= '0;
            top_tap_1 <= '0;
            top_tap_2 <= '0;
            mid_tap_0 <= '0;
            mid_tap_1 <= '0;
            mid_tap_2 <= '0;
            cur_tap_0 <= '0;
            cur_tap_1 <= '0;
            cur_tap_2 <= '0;
        end else if (we_in) begin
            if (y[0] == 1'b0) begin
                mid_rd       <= line_even[x];
                top_rd       <= line_odd[x];
                line_even[x] <= wData_in;
            end else begin
                mid_rd      <= line_odd[x];
                top_rd      <= line_even[x];
                line_odd[x] <= wData_in;
            end

            if (x == 0) begin
                top_tap_0 <= '0;
                top_tap_1 <= '0;
                top_tap_2 <= top_rd;
                mid_tap_0 <= '0;
                mid_tap_1 <= '0;
                mid_tap_2 <= mid_rd;
                cur_tap_0 <= '0;
                cur_tap_1 <= '0;
                cur_tap_2 <= wData_in;
            end else begin
                top_tap_0 <= top_tap_1;
                top_tap_1 <= top_tap_2;
                top_tap_2 <= top_rd;
                mid_tap_0 <= mid_tap_1;
                mid_tap_1 <= mid_tap_2;
                mid_tap_2 <= mid_rd;
                cur_tap_0 <= cur_tap_1;
                cur_tap_1 <= cur_tap_2;
                cur_tap_2 <= wData_in;
            end
        end
    end

    logic [ 9:0] sumR;
    logic [10:0] sumG;
    logic [ 9:0] sumB;
    logic [ 4:0] outR;
    logic [ 5:0] outG;
    logic [ 4:0] outB;

    always_comb begin
        sumR = R5(top_tap_0) + (R5(top_tap_1) << 1) + R5(top_tap_2) +
            (R5(mid_tap_0) << 1) + (R5(mid_tap_1) << 2) + (R5(mid_tap_2) << 1) +
            R5(cur_tap_0) + (R5(cur_tap_1) << 1) + R5(cur_tap_2);
        sumG = G6(top_tap_0) + (G6(top_tap_1) << 1) + G6(top_tap_2) +
            (G6(mid_tap_0) << 1) + (G6(mid_tap_1) << 2) + (G6(mid_tap_2) << 1) +
            G6(cur_tap_0) + (G6(cur_tap_1) << 1) + G6(cur_tap_2);
        sumB = B5(top_tap_0) + (B5(top_tap_1) << 1) + B5(top_tap_2) +
            (B5(mid_tap_0) << 1) + (B5(mid_tap_1) << 2) + (B5(mid_tap_2) << 1) +
            B5(cur_tap_0) + (B5(cur_tap_1) << 1) + B5(cur_tap_2);

        outR = sumR >> 4;
        outG = sumG >> 4;
        outB = sumB >> 4;
    end

    logic        we_out_nxt;
    logic [16:0] waddr_out_nxt;
    logic [15:0] wdata_out_nxt;

    always_comb begin
        if (we_in && win_valid) begin
            we_out_nxt = 1'b1;
            waddr_out_nxt = wAddr_in - (IMG_WIDTH + 17'd1);
            wdata_out_nxt = {outR, outG, outB};
        end else begin
            we_out_nxt    = 1'b0;
            waddr_out_nxt = '0;
            wdata_out_nxt = '0;
        end
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            we_out <= 1'b0;
            wAddr_out <= '0;
            wData_out <= '0;
        end else begin
            we_out <= we_out_nxt;
            wAddr_out <= waddr_out_nxt;
            wData_out <= wdata_out_nxt;
        end
    end

endmodule
