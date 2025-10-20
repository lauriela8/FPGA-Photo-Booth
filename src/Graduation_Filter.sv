`timescale 1ns / 1ps

module Graduation_Filter #(
    parameter int          IMG_WIDTH     = 320,
    parameter int          IMG_HEIGHT    = 240,
    // 8x8 font scaled 1.5x (3/2)
    parameter int          CHAR_W        = 8,
    parameter int          CHAR_H        = 8,
    parameter int          SCALE_NUM     = 3,        // 1.5x
    parameter int          SCALE_DEN     = 2,
    parameter int          TOP_MARGIN    = 6,
    parameter int          BOTTOM_MARGIN = 6,
    parameter int          MID_GAP       = 8,
    parameter logic [15:0] TEXT_COLOR    = 16'hFFFF  // RGB565 (white)
) (
    input logic clk,
    input logic reset,

    input logic we_in,
    input logic [$clog2(IMG_WIDTH*IMG_HEIGHT)-1:0] wAddr_in,
    input logic [15:0] wData_in,

    output logic we_out,
    output logic [$clog2(IMG_WIDTH*IMG_HEIGHT)-1:0] wAddr_out,
    output logic [15:0] wData_out
);
    // ----------------------------
    // 1) 텍스트 (정확한 길이)
    // ----------------------------
    // "Congradulation!!!"  = 17 chars
    localparam int TOP_LEN = 17;
    localparam logic [7:0] TOP_TXT[0:TOP_LEN-1] = '{
        8'd67,
        8'd111,
        8'd110,
        8'd103,
        8'd114,
        8'd97,
        8'd100,
        8'd117,
        8'd108,
        8'd97,
        8'd116,
        8'd105,
        8'd111,
        8'd110,
        8'd33,
        8'd33,
        8'd33
    };

    // "AI SYSTEM SEMICONDUCTOR" = 23 chars
    localparam int MID1_LEN = 23;
    localparam logic [7:0] MID1_TXT[0:MID1_LEN-1] = '{
        8'd65,
        8'd73,
        8'd32,
        8'd83,
        8'd89,
        8'd83,
        8'd84,
        8'd69,
        8'd77,
        8'd32,
        8'd83,
        8'd69,
        8'd77,
        8'd73,
        8'd67,
        8'd79,
        8'd78,
        8'd68,
        8'd85,
        8'd67,
        8'd84,
        8'd79,
        8'd82
    };

    // "DESIGN PROGRAM - CLASS 2" = 24 chars (마지막 '2' 포함)
    localparam int MID2_LEN = 24;
    localparam logic [7:0] MID2_TXT[0:MID2_LEN-1] = '{
        8'd68,
        8'd69,
        8'd83,
        8'd73,
        8'd71,
        8'd78,
        8'd32,
        8'd80,
        8'd82,
        8'd79,
        8'd71,
        8'd82,
        8'd65,
        8'd77,
        8'd32,
        8'd45,
        8'd32,
        8'd67,
        8'd76,
        8'd65,
        8'd83,
        8'd83,
        8'd32,
        8'd50
    };

    // ----------------------------
    // 2) 8x8 글리프 (MSB=left). 소문자는 자동 대문자 변환.
    // ----------------------------
    function automatic logic [7:0] glyph_row(input logic [7:0] ch_in,
                                             input int row);
        logic [7:0] ch, r;
        r = 8'h00;
        begin
            if (ch_in >= 8'd97 && ch_in <= 8'd122) ch = ch_in - 8'd32;
            else ch = ch_in;

            unique case (ch)
                8'd32: r = 8'h00;  // space
                8'd33:
                r = (row<=4)?8'b00011000:(row==6?8'b00011000:8'h00); // !
                8'd45: r = (row == 3) ? 8'b00111100 : 8'h00;  // '-'
                8'd50:
                case (row)  // '2'
                    0: r = 8'b00111100;
                    1: r = 8'b01000010;
                    2: r = 8'b00000100;
                    3: r = 8'b00011000;
                    4: r = 8'b00100000;
                    5: r = 8'b01000000;
                    6: r = 8'b01111110;
                    default: r = 8'h00;
                endcase

                8'd65:
                case (row)  // A
                    0: r = 8'b00011000;
                    1: r = 8'b00100100;
                    2: r = 8'b01000010;
                    3: r = 8'b01000010;
                    4: r = 8'b01111110;
                    5: r = 8'b01000010;
                    6: r = 8'b01000010;
                    default: r = 8'h00;
                endcase
                8'd67:
                case (row)  // C
                    0: r = 8'b00111100;
                    1: r = 8'b01000010;
                    2: r = 8'b01000000;
                    3: r = 8'b01000000;
                    4: r = 8'b01000000;
                    5: r = 8'b01000010;
                    6: r = 8'b00111100;
                    default: r = 8'h00;
                endcase
                8'd68:
                case (row)  // D
                    0: r = 8'b01111100;
                    1: r = 8'b01000010;
                    2: r = 8'b01000010;
                    3: r = 8'b01000010;
                    4: r = 8'b01000010;
                    5: r = 8'b01000010;
                    6: r = 8'b01111100;
                    default: r = 8'h00;
                endcase
                8'd69:
                case (row)  // E
                    0: r = 8'b01111110;
                    1: r = 8'b01000000;
                    2: r = 8'b01111100;
                    3: r = 8'b01000000;
                    4: r = 8'b01000000;
                    5: r = 8'b01000000;
                    6: r = 8'b01111110;
                    default: r = 8'h00;
                endcase
                8'd71:
                case (row)  // G
                    0: r = 8'b00111100;
                    1: r = 8'b01000010;
                    2: r = 8'b01000000;
                    3: r = 8'b01001110;
                    4: r = 8'b01000010;
                    5: r = 8'b01000010;
                    6: r = 8'b00111100;
                    default: r = 8'h00;
                endcase
                8'd73:
                case (row)  // I
                    0: r = 8'b01111110;
                    1: r = 8'b00011000;
                    2: r = 8'b00011000;
                    3: r = 8'b00011000;
                    4: r = 8'b00011000;
                    5: r = 8'b00011000;
                    6: r = 8'b01111110;
                    default: r = 8'h00;
                endcase
                8'd76:
                case (row)  // L
                    0: r = 8'b01000000;
                    1: r = 8'b01000000;
                    2: r = 8'b01000000;
                    3: r = 8'b01000000;
                    4: r = 8'b01000000;
                    5: r = 8'b01000000;
                    6: r = 8'b01111110;
                    default: r = 8'h00;
                endcase
                8'd77:
                case (row)  // M
                    0: r = 8'b01000010;
                    1: r = 8'b01100110;
                    2: r = 8'b01011010;
                    3: r = 8'b01000010;
                    4: r = 8'b01000010;
                    5: r = 8'b01000010;
                    6: r = 8'b01000010;
                    default: r = 8'h00;
                endcase
                8'd78:
                case (row)  // N
                    0: r = 8'b01000010;
                    1: r = 8'b01100010;
                    2: r = 8'b01010010;
                    3: r = 8'b01001010;
                    4: r = 8'b01000110;
                    5: r = 8'b01000010;
                    6: r = 8'b01000010;
                    default: r = 8'h00;
                endcase
                8'd79:
                case (row)  // O
                    0: r = 8'b00111100;
                    1: r = 8'b01000010;
                    2: r = 8'b01000010;
                    3: r = 8'b01000010;
                    4: r = 8'b01000010;
                    5: r = 8'b01000010;
                    6: r = 8'b00111100;
                    default: r = 8'h00;
                endcase
                8'd80:
                case (row)  // P
                    0: r = 8'b01111100;
                    1: r = 8'b01000010;
                    2: r = 8'b01111100;
                    3: r = 8'b01000000;
                    4: r = 8'b01000000;
                    5: r = 8'b01000000;
                    6: r = 8'b01000000;
                    default: r = 8'h00;
                endcase
                8'd82:
                case (row)  // R
                    0: r = 8'b01111100;
                    1: r = 8'b01000010;
                    2: r = 8'b01111100;
                    3: r = 8'b01001000;
                    4: r = 8'b01000100;
                    5: r = 8'b01000010;
                    6: r = 8'b01000010;
                    default: r = 8'h00;
                endcase
                8'd83:
                case (row)  // S
                    0: r = 8'b00111100;
                    1: r = 8'b01000000;
                    2: r = 8'b00111100;
                    3: r = 8'b00000010;
                    4: r = 8'b00000010;
                    5: r = 8'b01000010;
                    6: r = 8'b00111100;
                    default: r = 8'h00;
                endcase
                8'd84:
                case (row)  // T
                    0: r = 8'b01111110;
                    1: r = 8'b00011000;
                    2: r = 8'b00011000;
                    3: r = 8'b00011000;
                    4: r = 8'b00011000;
                    5: r = 8'b00011000;
                    6: r = 8'b00011000;
                    default: r = 8'h00;
                endcase
                8'd85:
                case (row)  // U
                    0: r = 8'b01000010;
                    1: r = 8'b01000010;
                    2: r = 8'b01000010;
                    3: r = 8'b01000010;
                    4: r = 8'b01000010;
                    5: r = 8'b01000010;
                    6: r = 8'b00111100;
                    default: r = 8'h00;
                endcase
                8'd89:
                case (row)  // Y
                    0: r = 8'b01000010;
                    1: r = 8'b00100100;
                    2: r = 8'b00011000;
                    3: r = 8'b00011000;
                    4: r = 8'b00011000;
                    5: r = 8'b00011000;
                    6: r = 8'b00011000;
                    default: r = 8'h00;
                endcase
                default: r = 8'h00;
            endcase
            return r;
        end
    endfunction

    // ----------------------------
    // 3) 스케일된 크기/위치
    // ----------------------------
    localparam int LINE_H = (CHAR_H * SCALE_NUM) / SCALE_DEN;
    localparam int TOP_W = (CHAR_W * TOP_LEN * SCALE_NUM) / SCALE_DEN;
    localparam int MID1_W = (CHAR_W * MID1_LEN * SCALE_NUM) / SCALE_DEN;
    localparam int MID2_W = (CHAR_W * MID2_LEN * SCALE_NUM) / SCALE_DEN;

    localparam int TOP_X = (IMG_WIDTH - TOP_W) / 2;
    localparam int MID1_X = (IMG_WIDTH - MID1_W) / 2;
    localparam int MID2_X = (IMG_WIDTH - MID2_W) / 2;

    localparam int TOP_Y = TOP_MARGIN;

    // 아래 블록(두 줄)의 전체 높이 = 2*LINE_H + MID_GAP
    localparam int BOT_BLOCK_H = (2 * LINE_H) + MID_GAP;
    localparam int BOT_Y1 = IMG_HEIGHT - BOTTOM_MARGIN - BOT_BLOCK_H;
    localparam int BOT_Y2 = BOT_Y1 + LINE_H + MID_GAP;

    // ----------------------------
    // 4) x,y 카운터 (나눗셈/나머지 제거)
    // ----------------------------
    logic [ $clog2(IMG_WIDTH)-1:0] x_i;
    logic [$clog2(IMG_HEIGHT)-1:0] y_i;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            x_i <= '0;
            y_i <= '0;
        end else if (we_in) begin
            if (wAddr_in == '0) begin
                x_i <= '0;
                y_i <= '0;
            end else begin
                if (x_i == IMG_WIDTH - 1) begin
                    x_i <= '0;
                    y_i <= (y_i == IMG_HEIGHT - 1) ? '0 : (y_i + 1'b1);
                end else begin
                    x_i <= x_i + 1'b1;
                end
            end
        end
    end

    // ----------------------------
    // 5) 텍스트 렌더 (인라인; 동적배열 인자 없음)
    // ----------------------------
    logic draw_top, draw_bot1, draw_bot2;
    always_comb begin
        draw_top  = 1'b0;
        draw_bot1 = 1'b0;
        draw_bot2 = 1'b0;

        // TOP
        if ((x_i>=TOP_X)&&(x_i<TOP_X+TOP_W)&&(y_i>=TOP_Y)&&(y_i<TOP_Y+LINE_H)) begin
            automatic int rx = x_i - TOP_X;
            automatic int ry = y_i - TOP_Y;
            automatic int ly0 = (ry * SCALE_DEN) / SCALE_NUM;
            automatic int cx0 = (rx * SCALE_DEN) / SCALE_NUM;
            automatic int idx = cx0 / CHAR_W;
            automatic int col = cx0 % CHAR_W;
            if ((ly0 >= 0 && ly0 < CHAR_H) && (idx >= 0 && idx < TOP_LEN)) begin
                automatic logic [7:0] bits;
                bits = glyph_row(TOP_TXT[idx], ly0);
                draw_top = bits[7-col];
            end
        end

        // BOTTOM line 1
        if ((x_i>=MID1_X)&&(x_i<MID1_X+MID1_W)&&(y_i>=BOT_Y1)&&(y_i<BOT_Y1+LINE_H)) begin
            automatic int rx = x_i - MID1_X;
            automatic int ry = y_i - BOT_Y1;
            automatic int ly0 = (ry * SCALE_DEN) / SCALE_NUM;
            automatic int cx0 = (rx * SCALE_DEN) / SCALE_NUM;
            automatic int idx = cx0 / CHAR_W;
            automatic int col = cx0 % CHAR_W;
            if ((ly0>=0&&ly0<CHAR_H)&&(idx>=0&&idx<MID1_LEN)) begin
                automatic logic [7:0] bits;
                bits = glyph_row(MID1_TXT[idx], ly0);
                draw_bot1 = bits[7-col];
            end
        end

        // BOTTOM line 2
        if ((x_i>=MID2_X)&&(x_i<MID2_X+MID2_W)&&(y_i>=BOT_Y2)&&(y_i<BOT_Y2+LINE_H)) begin
            automatic int rx = x_i - MID2_X;
            automatic int ry = y_i - BOT_Y2;
            automatic int ly0 = (ry * SCALE_DEN) / SCALE_NUM;
            automatic int cx0 = (rx * SCALE_DEN) / SCALE_NUM;
            automatic int idx = cx0 / CHAR_W;
            automatic int col = cx0 % CHAR_W;
            if ((ly0>=0&&ly0<CHAR_H)&&(idx>=0&&idx<MID2_LEN)) begin
                automatic logic [7:0] bits;
                bits = glyph_row(MID2_TXT[idx], ly0);
                draw_bot2 = bits[7-col];
            end
        end
    end

    // ----------------------------
    // 6) 출력(텍스트 > 원본)
    // ----------------------------
    logic [15:0] final_rgb;
    always_comb begin
        final_rgb = (draw_top || draw_bot1 || draw_bot2) ? TEXT_COLOR : wData_in;
    end

    // 1-cycle pass-through
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            we_out <= 1'b0;
            wAddr_out <= '0;
            wData_out <= '0;
        end else begin
            we_out    <= we_in;
            wAddr_out <= wAddr_in;
            wData_out <= final_rgb;
        end
    end
endmodule
