`timescale 1ns / 1ps

module Mirror_Filter #(
    parameter int IMG_WIDTH  = 320,
    parameter int IMG_HEIGHT = 240,
    // 0: 왼쪽→오른쪽 복사(대칭), 1: 오른쪽→왼쪽 복사(대칭)
    parameter int MODE       = 0
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        we_in,
    input  logic [16:0] wAddr_in,   // 0 .. IMG_WIDTH*IMG_HEIGHT-1
    input  logic [15:0] wData_in,   // RGB565
    output logic        we_out,
    output logic [16:0] wAddr_out,
    output logic [15:0] wData_out
);
    localparam int NUM_PIXELS = IMG_WIDTH * IMG_HEIGHT;
    localparam int ADDR_W = $clog2(NUM_PIXELS);
    localparam int X_W = $clog2(IMG_WIDTH);
    localparam int Y_W = $clog2(IMG_HEIGHT);
    localparam int MID = IMG_WIDTH / 2;

    // 입력 래치
    logic              we_q;
    logic [ADDR_W-1:0] addr_q;
    logic [      15:0] data_q;
    always_ff @(posedge clk) begin
        if (reset) begin
            we_q   <= 1'b0;
            addr_q <= '0;
            data_q <= '0;
        end else begin
            we_q   <= we_in;
            addr_q <= wAddr_in[ADDR_W-1:0];
            data_q <= wData_in;
        end
    end

    // (x,y) 분해
    logic [X_W-1:0] x;
    logic [Y_W-1:0] y;
    always_comb begin
        y = addr_q / IMG_WIDTH;
        x = addr_q - y * IMG_WIDTH;  // % 연산 대체
    end

    // 라인 버퍼 (핑퐁)
    // - curr_line[x] : 현재 라인 픽셀 저장
    // - prev_line[x] : 직전 라인 픽셀 (출력용)
    logic [15:0] linebuf0[0:IMG_WIDTH-1];
    logic [15:0] linebuf1[0:IMG_WIDTH-1];
    logic sel_curr;  // 0: use linebuf0 as current, 1: use linebuf1 as current

    // 현재 라인 쓰기
    always_ff @(posedge clk) begin
        if (reset) begin
            sel_curr <= 1'b0;
        end else if (we_q) begin
            if (!sel_curr) linebuf0[x] <= data_q;
            else linebuf1[x] <= data_q;

            // 라인 끝에서 토글 (x==IMG_WIDTH-1인 픽셀이 들어온 시점)
            if (x == IMG_WIDTH - 1) sel_curr <= ~sel_curr;
        end
    end

    // 직전 라인 읽기 선택
    function logic [15:0] prev_read(input logic [X_W-1:0] idx);
        if (!sel_curr)
            return linebuf1[idx];  // sel_curr=0이면 직전 라인은 buf1
        else return linebuf0[idx];  // sel_curr=1이면 직전 라인은 buf0
    endfunction

    // 출력: 직전 라인을 모드에 맞게 대칭 처리하여 현재 x 위치로 써준다
    // y==0 (첫 라인)은 직전 라인이 없으므로 원본 그대로 통과(또는 0)하도록 처리
    logic [15:0] out_data;
    logic [ADDR_W-1:0] out_addr;

    always_comb begin
        // 기본값
        out_addr = addr_q;     // 같은 (y,x)에 씀 (y-1 라인에 쓰고 싶다면 주소만 바꿔도 됨)
        if (y != 0) begin
            // 직전 라인 주소로 보낼지, 같은 라인 주소로 보낼지는 시스템에 따라 택1
            // 여기서는 같은 (y,x)로 쓰되, 데이터는 '직전 라인'을 대칭 처리한 값으로 만든다.
            // -> 결과적으로 최종 프레임에서 "한 라인 지연"으로 대칭이 반영됨.
            out_addr = y * IMG_WIDTH + x;

            if (MODE == 0) begin
                // 왼쪽 → 오른쪽 복사
                // 최종 화면: 왼쪽은 원본, 오른쪽은 왼쪽을 좌우대칭 복사
                if (x < MID) out_data = prev_read(x);  // 왼쪽은 그대로
                else
                    out_data = prev_read(
                        IMG_WIDTH - 1 - x
                    );  // 오른쪽은 왼쪽을 거울로
            end else begin
                // 오른쪽 → 왼쪽 복사
                // 최종 화면: 오른쪽은 원본, 왼쪽은 오른쪽을 좌우대칭 복사
                if (x < MID)
                    out_data = prev_read(
                        IMG_WIDTH - 1 - x
                    );  // 왼쪽은 오른쪽을 거울로
                else out_data = prev_read(x);  // 오른쪽은 그대로
            end
        end else begin
            // 첫 라인은 직전 라인이 없으므로 원본을 그대로 통과(원하면 0으로 클리어 가능)
            out_data = data_q;
            out_addr = y * IMG_WIDTH + x;
        end
    end

    // 출력 래치
    always_ff @(posedge clk) begin
        if (reset) begin
            we_out    <= 1'b0;
            wAddr_out <= '0;
            wData_out <= '0;
        end else begin
            we_out    <= we_q;
            wAddr_out <= out_addr;
            wData_out <= out_data;
        end
    end

    // synopsys translate_off
    always_ff @(posedge clk)
        if (!reset && we_out) begin
            assert (wAddr_out < NUM_PIXELS)
            else $error("Mirror_CopyHalf_to_Other: addr OOR");
        end
    // synopsys translate_on
endmodule
