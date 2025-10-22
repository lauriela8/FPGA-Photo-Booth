`timescale 1ns / 1ps

module Sticker_Filter #(
    parameter IMG_WIDTH        = 320,
    parameter IMG_HEIGHT       = 240,
    parameter RED_SEQUENCE_MIN = 8,    // 연속 빨간색 픽셀 최소 개수
    parameter BOX_SIZE         = 80    // 박스 크기 (80x80 픽셀)
) (
    input  logic        clk,
    input  logic        reset,
    // from MemController
    input  logic        we_in,
    input  logic [16:0] wAddr_in,
    input  logic [15:0] wData_in,     // RGB565
    // 스티커 버튼 입력
    input  logic        btn_sticker,  // 스티커 표시 버튼
    //sel image
    input  logic        btn_left,
    input  logic        btn_right,
    // to frame_buffer
    output logic        we_out,
    output logic [16:0] wAddr_out,
    output logic [15:0] wData_out
);

    // ============================================================
    // RGB565 → 빨간색 검출
    // ============================================================
    logic [4:0] in_r, in_g, in_b;
    logic is_red;

    assign in_r = wData_in[15:11];  // 5비트 빨간색
    assign in_g = wData_in[10:5];  // 6비트 초록색  
    assign in_b = wData_in[4:0];  // 5비트 파란색

    always_ff @(posedge clk) begin
        if (reset) begin
            is_red <= 0;
        end else if (we_in) begin
            // 빨간색 검출: R이 높고, G와 B가 낮아야 함
            is_red <= (in_r > 14) && (in_g < 13) && (in_b < 13);
        end
    end

    // ============================================================
    // 연속된 빨간색 픽셀 6개 이상 찾기 (프레임 끝에서 업데이트)
    // ============================================================
    logic [7:0] red_sequence_count;  // 현재 연속 빨간색 픽셀 개수
    logic [7:0] temp_red_col, temp_red_row;  // 임시 저장 좌표
    logic temp_red_detected;  // 임시 감지 플래그
    logic [7:0] red_center_col;                      // 박스 중심 열 (프레임 끝에서 업데이트)
    logic [7:0] red_center_row;                      // 박스 중심 행 (프레임 끝에서 업데이트)
    logic       red_detected;                        // 빨간색 감지됨 (프레임 끝에서 업데이트)

    // ============================================================
    // 스티커 시스템 (5초간 표시)
    // ============================================================
    logic [7:0] sticker_center_col;  // 스티커 중심 열
    logic [7:0] sticker_center_row;  // 스티커 중심 행
    logic sticker_active;  // 스티커 활성화 플래그
    logic [26:0] sticker_timer;                      // 5초 타이머 (25MHz 기준, 125,000,000 클록)
    logic sticker_trigger;  // 스티커 트리거 (버튼 눌림 감지)

    logic [$clog2(IMG_WIDTH)-1:0] col_cnt;
    logic [$clog2(IMG_HEIGHT)-1:0] row_cnt;

    // 주소 파이프라인 정렬 (4단계 파이프라인)
    logic [16:0] addr_d1, addr_d2, addr_d3, addr_d4;
    logic we_d1, we_d2, we_d3, we_d4;

    // 좌표 파이프라인 (filtered_skin과 동기화)
    logic [$clog2(IMG_WIDTH)-1:0]
        col_cnt_d1, col_cnt_d2, col_cnt_d3, col_cnt_d4;
    logic [$clog2(IMG_HEIGHT)-1:0]
        row_cnt_d1, row_cnt_d2, row_cnt_d3, row_cnt_d4;


    always_ff @(posedge clk) begin
        if (reset) begin
            col_cnt <= 0;
            row_cnt <= 0;
            red_sequence_count <= 0;
            temp_red_col <= 0;
            temp_red_row <= 0;
            temp_red_detected <= 0;
            red_center_col <= 0;
            red_center_row <= 0;
            red_detected <= 0;
            sticker_center_col <= 0;
            sticker_center_row <= 0;
            sticker_active <= 0;
            sticker_timer <= 0;
            sticker_trigger <= 0;
            addr_d1 <= 0;
            addr_d2 <= 0;
            addr_d3 <= 0;
            addr_d4 <= 0;
            we_d1 <= 0;
            we_d2 <= 0;
            we_d3 <= 0;
            we_d4 <= 0;
            col_cnt_d1 <= 0;
            col_cnt_d2 <= 0;
            col_cnt_d3 <= 0;
            col_cnt_d4 <= 0;
            row_cnt_d1 <= 0;
            row_cnt_d2 <= 0;
            row_cnt_d3 <= 0;
            row_cnt_d4 <= 0;
        end else if (we_in) begin
            // 파이프라인 (4단계)
            addr_d1 <= wAddr_in;
            addr_d2 <= addr_d1;
            addr_d3 <= addr_d2;
            addr_d4 <= addr_d3;
            we_d1 <= we_in;
            we_d2 <= we_d1;
            we_d3 <= we_d2;
            we_d4 <= we_d3;

            // 좌표 파이프라인
            col_cnt_d1 <= col_cnt;
            col_cnt_d2 <= col_cnt_d1;
            col_cnt_d3 <= col_cnt_d2;
            col_cnt_d4 <= col_cnt_d3;
            row_cnt_d1 <= row_cnt;
            row_cnt_d2 <= row_cnt_d1;
            row_cnt_d3 <= row_cnt_d2;
            row_cnt_d4 <= row_cnt_d3;

            // 프레임 시작 시 리셋
            if (row_cnt == 0 && col_cnt == 0) begin
                red_sequence_count <= 0;
                temp_red_detected  <= 0;
            end  // 연속된 빨간색 픽셀 카운트
            else if (is_red) begin
                red_sequence_count <= red_sequence_count + 1;
                // RED_SEQUENCE_MIN개 이상 연속되면 임시 좌표 저장
                if (red_sequence_count >= (RED_SEQUENCE_MIN - 1)) begin  // 0부터 시작하므로 -1
                    temp_red_col <= col_cnt;
                    temp_red_row <= row_cnt;
                    temp_red_detected <= 1;
                end
            end  // 빨간색이 아니면 연속 카운트 리셋
            else begin
                red_sequence_count <= 0;
            end

            // 프레임 끝에서 최종 좌표 업데이트
            if (row_cnt == IMG_HEIGHT - 1 && col_cnt == IMG_WIDTH - 1) begin
                if (temp_red_detected) begin
                    red_center_col <= temp_red_col;
                    red_center_row <= temp_red_row;
                    red_detected   <= 1;
                end else begin
                    red_center_col <= 0;
                    red_center_row <= 0;
                    red_detected   <= 0;
                end
            end

            // 스티커 트리거 감지 (버튼 눌림)
            sticker_trigger <= btn_sticker;

            // 스티커 시스템 로직
            if (btn_sticker && !sticker_trigger && red_detected) begin
                // 버튼이 눌렸고, 빨간색이 감지된 상태일 때
                // 경계 제한 없이 전체 화면에서 스티커 생성
                sticker_center_col <= red_center_col;
                sticker_center_row <= red_center_row;
                sticker_active <= 1;
                sticker_timer <= 0;
            end else if (sticker_active) begin
                // 5초 타이머 카운트
                if (sticker_timer >= 125_000_000 - 1) begin  // 5초 (25MHz)
                    sticker_active <= 0;
                    sticker_timer  <= 0;
                end else begin
                    sticker_timer <= sticker_timer + 1;
                end
            end

            // 좌표 카운터
            if (col_cnt == IMG_WIDTH - 1) begin
                col_cnt <= 0;
                if (row_cnt == IMG_HEIGHT - 1) row_cnt <= 0;
                else row_cnt <= row_cnt + 1;
            end else begin
                col_cnt <= col_cnt + 1;
            end
        end
    end

    // ============================================================
    // 빨간색 감지 신호를 파이프라인으로 전달
    // ============================================================
    logic red_detected_d1, red_detected_d2, red_detected_d3, red_detected_d4;
    logic [7:0]
        red_center_col_d1,
        red_center_col_d2,
        red_center_col_d3,
        red_center_col_d4;
    logic [7:0]
        red_center_row_d1,
        red_center_row_d2,
        red_center_row_d3,
        red_center_row_d4;
    logic is_red_d1, is_red_d2, is_red_d3, is_red_d4;

    logic [15:0] wData_in_d1, wData_in_d2, wData_in_d3, wData_in_d4;

    // 스티커 파이프라인
    logic
        sticker_active_d1,
        sticker_active_d2,
        sticker_active_d3,
        sticker_active_d4;
    logic [7:0]
        sticker_center_col_d1,
        sticker_center_col_d2,
        sticker_center_col_d3,
        sticker_center_col_d4;
    logic [7:0]
        sticker_center_row_d1,
        sticker_center_row_d2,
        sticker_center_row_d3,
        sticker_center_row_d4;

    // ImageROM 인스턴스
    logic [11:0] rom_addr;
    logic [15:0] rom_data;

    ImageROM #(
        .IMG_WIDTH (64),
        .IMG_HEIGHT(64),
        .ADDR_WIDTH(12)   // 64*64 = 4096, 2^12 = 4096
    ) U_image (
        .clk(clk),
        .btn_right(btn_right),
        .btn_left(btn_left),
        .addr(rom_addr),
        .data(rom_data)
    );

    always_ff @(posedge clk) begin
        if (reset) begin
            red_detected_d1 <= 0;
            red_detected_d2 <= 0;
            red_detected_d3 <= 0;
            red_detected_d4 <= 0;
            red_center_col_d1 <= 0;
            red_center_col_d2 <= 0;
            red_center_col_d3 <= 0;
            red_center_col_d4 <= 0;
            red_center_row_d1 <= 0;
            red_center_row_d2 <= 0;
            red_center_row_d3 <= 0;
            red_center_row_d4 <= 0;
            is_red_d1 <= 0;
            is_red_d2 <= 0;
            is_red_d3 <= 0;
            is_red_d4 <= 0;
            wData_in_d1 <= 0;
            wData_in_d2 <= 0;
            wData_in_d3 <= 0;
            wData_in_d4 <= 0;
            sticker_active_d1 <= 0;
            sticker_active_d2 <= 0;
            sticker_active_d3 <= 0;
            sticker_active_d4 <= 0;
            sticker_center_col_d1 <= 0;
            sticker_center_col_d2 <= 0;
            sticker_center_col_d3 <= 0;
            sticker_center_col_d4 <= 0;
            sticker_center_row_d1 <= 0;
            sticker_center_row_d2 <= 0;
            sticker_center_row_d3 <= 0;
            sticker_center_row_d4 <= 0;
        end else begin
            red_detected_d1 <= red_detected;
            red_detected_d2 <= red_detected_d1;
            red_detected_d3 <= red_detected_d2;
            red_detected_d4 <= red_detected_d3;

            red_center_col_d1 <= red_center_col;
            red_center_col_d2 <= red_center_col_d1;
            red_center_col_d3 <= red_center_col_d2;
            red_center_col_d4 <= red_center_col_d3;

            red_center_row_d1 <= red_center_row;
            red_center_row_d2 <= red_center_row_d1;
            red_center_row_d3 <= red_center_row_d2;
            red_center_row_d4 <= red_center_row_d3;


            is_red_d1 <= is_red;
            is_red_d2 <= is_red_d1;
            is_red_d3 <= is_red_d2;
            is_red_d4 <= is_red_d3;

            wData_in_d1 <= wData_in;
            wData_in_d2 <= wData_in_d1;
            wData_in_d3 <= wData_in_d2;
            wData_in_d4 <= wData_in_d3;

            // 스티커 파이프라인
            sticker_active_d1 <= sticker_active;
            sticker_active_d2 <= sticker_active_d1;
            sticker_active_d3 <= sticker_active_d2;
            sticker_active_d4 <= sticker_active_d3;

            sticker_center_col_d1 <= sticker_center_col;
            sticker_center_col_d2 <= sticker_center_col_d1;
            sticker_center_col_d3 <= sticker_center_col_d2;
            sticker_center_col_d4 <= sticker_center_col_d3;

            sticker_center_row_d1 <= sticker_center_row;
            sticker_center_row_d2 <= sticker_center_row_d1;
            sticker_center_row_d3 <= sticker_center_row_d2;
            sticker_center_row_d4 <= sticker_center_row_d3;
        end
    end

    // ============================================================
    // 스티커 오버레이 시스템
    // ============================================================

    // 스티커 영역 체크 (64x64 이미지)
    wire in_sticker_area = (col_cnt_d4 >= sticker_center_col_d4 - 32) && 
                          (col_cnt_d4 <= sticker_center_col_d4 + 31) &&
                          (row_cnt_d4 >= sticker_center_row_d4 - 32) && 
                          (row_cnt_d4 <= sticker_center_row_d4 + 31);

    // ROM 주소 계산 (64x64 이미지 내의 상대 좌표)
    wire [5:0] sticker_rel_x = col_cnt_d4 - (sticker_center_col_d4 - 32);
    wire [5:0] sticker_rel_y = row_cnt_d4 - (sticker_center_row_d4 - 32);
    wire [11:0] sticker_rom_addr = {sticker_rel_y, sticker_rel_x};  // y*64 + x

    // ROM 주소 업데이트
    always_ff @(posedge clk) begin
        if (in_sticker_area && sticker_active_d4) begin
            rom_addr <= sticker_rom_addr;
        end else begin
            rom_addr <= 0;
        end
    end

    // ============================================================
    // 간단한 박스 그리기 (프레임 단위 업데이트) - 비활성화
    // ============================================================

    // 경계 체크
    wire at_border_d4 = (row_cnt_d4 < 2) || (col_cnt_d4 < 2) ||
                       (row_cnt_d4 >= IMG_HEIGHT-2) || (col_cnt_d4 >= IMG_WIDTH-2);

    // 박스 영역 체크 (프레임 끝에서 업데이트되는 red 좌표 사용)
    wire in_box = (col_cnt_d4 >= red_center_col_d4 - BOX_SIZE/2) && 
                  (col_cnt_d4 <= red_center_col_d4 + BOX_SIZE/2) &&
                  (row_cnt_d4 >= red_center_row_d4 - BOX_SIZE/2) && 
                  (row_cnt_d4 <= red_center_row_d4 + BOX_SIZE/2);

    // 박스 테두리 체크 (2픽셀 두께, 프레임 끝에서 업데이트되는 red 좌표 사용)
    wire is_box_border = in_box && red_detected_d4 && (
        (col_cnt_d4 == red_center_col_d4 - BOX_SIZE/2) || (col_cnt_d4 == red_center_col_d4 + BOX_SIZE/2) ||
        (row_cnt_d4 == red_center_row_d4 - BOX_SIZE/2) || (row_cnt_d4 == red_center_row_d4 + BOX_SIZE/2) ||
        (col_cnt_d4 == red_center_col_d4 - BOX_SIZE/2 + 1) || (col_cnt_d4 == red_center_col_d4 + BOX_SIZE/2 - 1) ||
        (row_cnt_d4 == red_center_row_d4 - BOX_SIZE/2 + 1) || (row_cnt_d4 == red_center_row_d4 + BOX_SIZE/2 - 1)
    );

    // ============================================================
    // 출력 (RGB565) — 원본 픽셀 + 스티커 오버레이
    // ============================================================
    logic [15:0] dout_reg;
    logic centroid_valid;
    logic [7:0] centroid_x;
    logic [7:0] centroid_y;

    always_ff @(posedge clk) begin
        if (reset) dout_reg <= 16'h0000;
        else if (we_d4) begin  // 4단계 파이프라인된 we 사용
            if (in_sticker_area && sticker_active_d4) begin
                // 스티커 영역 (최우선)
                if (rom_data != 16'h0000) begin  // 투명이 아닌 경우
                    dout_reg <= rom_data;  // ROM에서 읽은 스티커 데이터
                end else begin
                    dout_reg <= wData_in_d4;  // 투명한 경우 원본 픽셀
                end
            end else begin
                // 모든 경우에 원본 픽셀 출력
                dout_reg <= wData_in_d4;
            end
        end
    end

    // 주소/WE 파이프라인 맞춰서 출력 (4단계 파이프라인)
    always_ff @(posedge clk) begin
        if (reset) begin
            wAddr_out <= 0;
            we_out    <= 0;
        end else begin
            wAddr_out <= addr_d4;
            we_out    <= we_d4;
        end
    end

    // 빨간색 감지 결과 출력
    always_ff @(posedge clk) begin
        if (reset) begin
            centroid_valid <= 0;
            centroid_x <= 0;
            centroid_y <= 0;
        end else begin
            centroid_valid <= red_detected;  // 빨간색 감지 유효 신호
            centroid_x     <= red_center_col;  // 빨간색 중심 x 좌표
            centroid_y     <= red_center_row;  // 빨간색 중심 y 좌표
        end
    end

    assign wData_out = dout_reg;

endmodule


// ImageROM 모듈 (기존 Sticker_Filter에서 가져옴)
module ImageROM #(
    parameter IMG_WIDTH  = 64,
    parameter IMG_HEIGHT = 64,
    parameter ADDR_WIDTH = 12   // 64*64 = 4096, 2^12 = 4096
) (
    input logic clk,
    input logic btn_right,
    input logic btn_left,
    input logic [ADDR_WIDTH-1:0] addr,
    output logic [15:0] data
);

    // 64x64 = 4096 픽셀의 RGB565 데이터
    reg [15:0] rom1 [0:4095];
    reg [15:0] rom2 [0:4095];
    reg [15:0] rom3 [0:4095];
    reg [15:0] rom4 [0:4095];
    reg [15:0] rom5 [0:4095];
    reg [15:0] rom6 [0:4095];
    reg [15:0] rom7 [0:4095];
    reg [15:0] rom8 [0:4095];
    reg [15:0] rom9 [0:4095];
    reg [15:0] rom10[0:4095];

    typedef enum {
        LUCKYBAG,
        HEART,
        SUNGLASSES,
        TURTLE,
        GHOST,
        HAMSTER,
        PREREN,
        AI,
        JJANGU,
        NEZCO
    } rom_type;

    rom_type state, next_state;

    // image.rom 파일에서 데이터 로드
    initial begin
        $readmemh("luckybag.mem", rom1);
        $readmemh("heart.mem", rom2);
        $readmemh("sunglass.mem", rom3);
        $readmemh("turtle.mem", rom4);
        $readmemh("ghost.mem", rom5);
        $readmemh("hamster.mem", rom6);
        $readmemh("preren.mem", rom7);
        $readmemh("ai.mem", rom8);
        $readmemh("jjangu.mem", rom9);
        $readmemh("nezco.mem", rom10);
    end

    // 클록 동기 출력
    always_ff @(posedge clk) begin
        state <= next_state;
    end

    always_ff @(posedge clk) begin
        case (state)
            LUCKYBAG:   data <= rom1[addr];
            HEART:      data <= rom2[addr];
            SUNGLASSES: data <= rom3[addr];
            TURTLE:     data <= rom4[addr];
            GHOST:      data <= rom5[addr];
            HAMSTER:    data <= rom6[addr];
            PREREN:     data <= rom7[addr];
            AI:         data <= rom8[addr];
            JJANGU:     data <= rom9[addr];
            NEZCO:      data <= rom10[addr];
            default:    data <= rom1[addr];
        endcase
    end

    always_comb begin
        next_state = state;
        case (state)
            LUCKYBAG: begin
                if (btn_right) next_state = HEART;
                else if (btn_left) next_state = NEZCO;
            end
            HEART: begin
                if (btn_right) next_state = SUNGLASSES;
                else if (btn_left) next_state = LUCKYBAG;
            end
            SUNGLASSES: begin
                if (btn_right) next_state = TURTLE;
                else if (btn_left) next_state = HEART;
            end
            TURTLE: begin
                if (btn_right) next_state = GHOST;
                else if (btn_left) next_state = SUNGLASSES;
            end
            GHOST: begin
                if (btn_right) next_state = HAMSTER;
                else if (btn_left) next_state = TURTLE;
            end
            HAMSTER: begin
                if (btn_right) next_state = PREREN;
                else if (btn_left) next_state = GHOST;
            end
            PREREN: begin
                if (btn_right) next_state = AI;
                else if (btn_left) next_state = HAMSTER;
            end
            AI: begin
                if (btn_right) next_state = JJANGU;
                else if (btn_left) next_state = PREREN;
            end
            JJANGU: begin
                if (btn_right) next_state = NEZCO;
                else if (btn_left) next_state = AI;
            end
            NEZCO: begin
                if (btn_right) next_state = LUCKYBAG;
                else if (btn_left) next_state = JJANGU;
            end
        endcase
    end
endmodule
