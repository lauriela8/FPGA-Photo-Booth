`timescale 1ns / 1ps

module UART (
    input  logic clk,
    input  logic reset,
    input  logic rx,
    output logic tx,

    input logic [3:0] sel,
    input logic [1:0] vga_sw,
    input logic       btn_sticker,
    input logic       btn_left,
    input logic       btn_right,

    output logic [3:0] sel_final,
    output logic [1:0] vga_sw_final,
    output logic btn_sticker_final,
    output logic btn_right_final,
    output logic btn_left_final
);
    logic       rx_done;
    logic [7:0] rx_data;

    uart_intf U_uart_intf (
        .clk    (clk),
        .reset  (reset),
        .start  (rx_done),
        .tx_data(rx_data),
        .tx_done(),
        .tx     (tx),
        .rx     (rx),
        .rx_done(rx_done),
        .rx_data(rx_data),
        .tx_busy()
    );

    logic [3:0] uart_btn_code;
    logic [1:0] uart_sw1415_code;
    logic [2:0] uart_button_code;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            uart_btn_code <= 4'b0000;
        end else if (rx_done) begin
            case (rx_data)
                "0": uart_btn_code <= 4'b0000;  // original
                "1": uart_btn_code <= 4'b0001;  // Gaussian
                "2": uart_btn_code <= 4'b0010;  // Sobel
                "3": uart_btn_code <= 4'b0011;  // Graduation
                "4": uart_btn_code <= 4'b0100;  // Warm
                "5": uart_btn_code <= 4'b0101;  // Cool
                "6": uart_btn_code <= 4'b0110;  // Ghost
                "7": uart_btn_code <= 4'b0111;  // Cartoon
                "8": uart_btn_code <= 4'b1000;  // PopArt
                "9": uart_btn_code <= 4'b1001;  // Mirror
                ".": uart_btn_code <= 4'b1010;  // Sticker
                default: uart_btn_code <= uart_btn_code;
            endcase
        end
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            uart_sw1415_code <= 2'b00;
        end else if (rx_done) begin
            case (rx_data)
                "z": uart_sw1415_code <= 2'b00;  // original
                "x": uart_sw1415_code <= 2'b01;  // full
                "c": uart_sw1415_code <= 2'b10;  // 4cut

                default: uart_sw1415_code <= uart_sw1415_code;
            endcase
        end
    end

    logic [3:0] hold_cnt;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            uart_button_code <= 3'b100;  // idle
            hold_cnt <= 0;
        end else if (rx_done) begin
            case (rx_data)
                "s": uart_button_code <= 3'b000;
                "w": uart_button_code <= 3'b001;
                "a": uart_button_code <= 3'b010;
                "d": uart_button_code <= 3'b011;
            endcase
            hold_cnt <= 4'd7;  // 7클럭 정도 유지
        end else if (hold_cnt != 0) begin
            hold_cnt <= hold_cnt - 1;
            uart_button_code <= uart_button_code;  // 값 유지
        end else begin
            uart_button_code <= 3'b100;  // idle 복귀
        end
    end

    assign btn_sel    = uart_button_code;
    assign filter_sel = uart_btn_code;
    assign cut_sel    = uart_sw1415_code;

    bridge U_bridge (
        .sel              (sel),
        .filter_sel       (uart_btn_code),
        .vga_sw           (vga_sw),
        .cut_sel          (uart_sw1415_code),
        .btn_sel          (uart_button_code),
        .btn_sticker      (btn_sticker),
        .btn_left         (btn_left),
        .btn_right        (btn_right),
        .sel_final        (sel_final),
        .vga_sw_final     (vga_sw_final),
        .btn_sticker_final(btn_sticker_final),
        .btn_right_final  (btn_right_final),
        .btn_left_final   (btn_left_final)
    );
endmodule

module uart_intf (
    input logic       clk,
    input logic       reset,
    input logic       start,
    input logic [7:0] tx_data,
    input logic       rx,

    output logic tx_busy,
    output logic tx_done,
    output logic rx_done,
    output logic [7:0] rx_data,
    output logic tx
);
    logic br_tick;

    baudrate_gen U_BAUD_GEN (
        .clk    (clk),
        .reset  (reset),
        .br_tick(br_tick)
    );
    transmitter U_Transmitter (
        .clk    (clk),
        .reset  (reset),
        .br_tick(br_tick),
        .start  (start),
        .tx_data(tx_data),
        .tx_busy(tx_busy),
        .tx_done(tx_done),
        .tx     (tx)
    );
    receiver U_Reciever (
        .clk    (clk),
        .rst    (reset),
        .tick   (br_tick),
        .rx     (rx),
        .rx_done(rx_done),
        .rx_data(rx_data)
    );

endmodule

module baudrate_gen (
    input  logic clk,
    input  logic reset,
    output logic br_tick
);
    logic [$clog2(100_000_000/9600/16)-1:0] br_counter;

    always_ff @(posedge clk, posedge reset) begin
        if (reset) begin
            br_counter <= 0;
            br_tick <= 0;
        end else begin
            if (br_counter == 100_000_000 / 9600 / 16 - 1) begin
                br_counter <= 0;
                br_tick <= 1;
            end else begin
                br_counter <= br_counter + 1;
                br_tick <= 0;
            end
        end
    end
endmodule

module receiver (
    input clk,
    input rst,
    input tick,
    input rx,
    output rx_done,
    output [7:0] rx_data
);
    typedef enum {
        IDLE,
        START,
        DATA,
        STOP
    } rx_state_e;

    rx_state_e rx_state, rx_next_state;

    logic rx_done_reg, rx_done_next;
    logic [3:0] bit_count_reg, bit_count_next;
    logic [4:0] tick_count_reg, tick_count_next;
    logic [7:0] rx_data_reg, rx_data_next;

    assign rx_done = rx_done_reg;
    assign rx_data = rx_data_reg;

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            rx_state       <= IDLE;
            rx_done_reg    <= 0;
            rx_data_reg    <= 0;
            bit_count_reg  <= 0;
            tick_count_reg <= 0;
        end else begin
            rx_state       <= rx_next_state;
            rx_done_reg    <= rx_done_next;
            rx_data_reg    <= rx_data_next;
            bit_count_reg  <= bit_count_next;
            tick_count_reg <= tick_count_next;
        end
    end

    always_comb begin
        rx_next_state = rx_state;
        tick_count_next = tick_count_reg;
        bit_count_next = bit_count_reg;
        rx_done_next = rx_done_reg;
        rx_data_next = rx_data_reg;
        case (rx_state)
            IDLE: begin
                tick_count_next = 0;
                bit_count_next = 0;
                rx_done_next = 1'b0;
                if (rx == 1'b0) begin
                    rx_next_state = START;
                end
            end
            START: begin
                if (tick == 1'b1) begin
                    if (tick_count_reg == 7) begin
                        rx_next_state   = DATA;
                        tick_count_next = 0;
                    end else begin
                        tick_count_next = tick_count_reg + 1;
                        rx_next_state   = START;
                    end
                end
            end
            DATA: begin
                if (tick == 1'b1) begin
                    if (tick_count_reg == 15) begin
                        rx_data_next = {rx, rx_data_reg[7:1]};
                        if (bit_count_reg == 7) begin
                            rx_next_state   = STOP;
                            tick_count_next = 0;
                        end else begin
                            rx_next_state   = DATA;
                            bit_count_next  = bit_count_reg + 1;
                            tick_count_next = 0;
                        end
                    end else begin
                        tick_count_next = tick_count_reg + 1;
                    end
                end
            end
            STOP: begin
                if (tick == 1'b1) begin
                    if (tick_count_reg == 23) begin  //15 + 8
                        rx_done_next  = 1'b1;
                        rx_next_state = IDLE;
                    end else begin
                        tick_count_next = tick_count_reg + 1;
                    end
                end
            end
        endcase
    end
endmodule

module transmitter (
    input  logic       clk,
    input  logic       reset,
    input  logic       br_tick,
    input  logic [7:0] tx_data,
    input  logic       start,
    output logic       tx_busy,
    output logic       tx_done,
    output logic       tx
);
    typedef enum {
        IDLE,
        START,
        DATA,
        STOP
    } tx_state_e;

    tx_state_e tx_state, tx_next_state;

    logic [7:0] temp_data_reg, temp_data_next;
    logic [3:0] tick_cnt_reg, tick_cnt_next;
    logic [2:0] bit_cnt_reg, bit_cnt_next;
    logic tx_reg, tx_next, tx_busy_next, tx_busy_reg, tx_done_reg, tx_done_next;

    assign tx = tx_reg;
    assign tx_busy = tx_busy_reg;
    assign tx_done = tx_done_reg;

    always_ff @(posedge clk, posedge reset) begin
        if (reset) begin
            tx_state      <= IDLE;
            temp_data_reg <= 0;
            tx_reg        <= 1;
            tick_cnt_reg  <= 0;
            bit_cnt_reg   <= 0;
            tx_done_reg   <= 0;
            tx_busy_reg   <= 0;
        end else begin
            tx_state      <= tx_next_state;
            temp_data_reg <= temp_data_next;
            tx_reg        <= tx_next;
            tick_cnt_reg  <= tick_cnt_next;
            bit_cnt_reg   <= bit_cnt_next;
            tx_done_reg   <= tx_done_next;
            tx_busy_reg   <= tx_busy_next;
        end
    end

    always_comb begin
        tx_next_state  = tx_state;
        temp_data_next = temp_data_reg;
        tx_next        = tx_reg;
        tick_cnt_next  = tick_cnt_reg;
        bit_cnt_next   = bit_cnt_reg;
        tx_done_next   = tx_done_reg;
        tx_busy_next   = tx_busy_reg;
        case (tx_state)
            IDLE: begin
                tx_next = 1;
                tx_done_next = 0;
                tx_busy_next = 0;
                if (start) begin
                    tx_next_state  = START;
                    temp_data_next = tx_data;
                    tick_cnt_next  = 0;
                    bit_cnt_next   = 0;
                    tx_busy_next   = 1;
                end
            end
            START: begin
                tx_next = 0;
                if (br_tick) begin
                    if (tick_cnt_reg == 15) begin
                        tx_next_state = DATA;
                        tick_cnt_next = 0;
                    end else begin
                        tick_cnt_next = tick_cnt_reg + 1;
                    end
                end
            end
            DATA: begin
                tx_next = temp_data_reg[0];
                if (br_tick) begin
                    if (tick_cnt_reg == 15) begin
                        tick_cnt_next = 0;
                        if (bit_cnt_reg == 7) begin
                            tx_next_state = STOP;
                            bit_cnt_next  = 0;
                        end else begin
                            temp_data_next = {1'b0, temp_data_reg[7:1]};
                            bit_cnt_next   = bit_cnt_reg + 1;
                        end
                    end else begin
                        tick_cnt_next = tick_cnt_reg + 1;
                    end
                end
            end
            STOP: begin
                tx_next = 1;
                if (br_tick) begin
                    if (tick_cnt_reg == 15) begin
                        tx_next_state = IDLE;
                        tx_done_next  = 1;
                        tx_busy_next  = 0;
                        tick_cnt_next = 0;
                    end else begin
                        tick_cnt_next = tick_cnt_reg + 1;
                    end
                end
            end
        endcase
    end
endmodule

module bridge (
    input logic [3:0] sel,
    input logic [3:0] filter_sel,
    input logic [1:0] vga_sw,
    input logic [1:0] cut_sel,
    input logic [2:0] btn_sel,
    input logic       btn_sticker,
    input logic       btn_left,
    input logic       btn_right,

    output logic [3:0] sel_final,
    output logic [1:0] vga_sw_final,
    output logic btn_sticker_final,
    output logic btn_right_final,
    output logic btn_left_final
);
    logic btn_reset_uart;
    logic btn_sticker_uart;
    logic btn_left_uart;
    logic btn_right_uart;
    logic reset_final;

    always_comb begin
        btn_reset_uart   = (btn_sel == 3'b000);  // "s"
        btn_sticker_uart = (btn_sel == 3'b001);  // "w"
        btn_left_uart    = (btn_sel == 3'b010);  // "a"
        btn_right_uart   = (btn_sel == 3'b011);  // "d"
    end

    assign btn_sticker_final = btn_sticker | btn_sticker_uart;
    assign btn_left_final    = btn_left_uart | btn_left;
    assign btn_right_final   = btn_right_uart | btn_right;
    assign sel_final         = (sel != 4'b0000) ? sel : filter_sel;
    assign vga_sw_final      = (vga_sw != 2'b00) ? vga_sw : cut_sel;

endmodule
