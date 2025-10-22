`timescale 1ns / 1ps

module ISP_Top (
    // Global Signals
    input  logic       clk,
    input  logic       reset,
    // Filter Port
    input  logic [3:0] sel,
    input  logic [1:0] vga_sw,
    input  logic       btn_sticker,
    input  logic       btn_left,
    input  logic       btn_right,
    // Ov7670 Port
    output logic       ov7670_xclk,
    input  logic       ov7670_pclk,
    input  logic       ov7670_href,
    input  logic       ov7670_vsync,
    input  logic [7:0] ov7670_data,
    // External Port
    output logic       h_sync,
    output logic       v_sync,
    output logic [3:0] r_port,
    output logic [3:0] g_port,
    output logic [3:0] b_port,
    // Sccb Port
    output logic       SCL,
    output logic       SDA,
    // Uart Port
    input  logic       rx,
    output logic       tx
);
    logic        ov7670_we;
    logic [16:0] ov7670_wAddr;
    logic [15:0] ov7670_wData;

    logic        vga_pclk;
    logic [ 9:0] vga_x_pixel;
    logic [ 9:0] vga_y_pixel;
    logic        vga_DE;

    logic        vga_den;
    logic [16:0] vga_rAddr;
    logic [15:0] vga_rData;

    logic        o_we_out;
    logic [16:0] o_wAddr;
    logic [15:0] o_rData;

    assign ov7670_xclk = vga_pclk;

    logic [3:0] sel_final;
    logic [1:0] vga_sw_final;
    logic btn_sticker_final;
    logic [3:0] filter_sel;
    logic [1:0] cut_sel;
    logic [1:0] btn_sel;

    UART U_UART (
        .clk              (clk),
        .reset            (reset),
        .rx               (rx),
        .tx               (tx),
        .sel              (sel),
        .vga_sw           (vga_sw),
        .btn_sticker      (btn_sticker),
        .btn_left         (btn_left),
        .btn_right        (btn_right),
        .sel_final        (sel_final),
        .vga_sw_final     (vga_sw_final),
        .btn_sticker_final(btn_sticker_final),
        .btn_right_final  (btn_right_final),
        .btn_left_final   (btn_left_final)
    );

    SCCB U_SCCB (
        .clk  (clk),
        .reset(reset),
        .SCL  (SCL),
        .SDA  (SDA)
    );

    OV7670_MemController U_OV7670_MemController (
        .clk        (ov7670_pclk),
        .reset      (reset),
        .href       (ov7670_href),
        .vsync      (ov7670_vsync),
        .ov7670_data(ov7670_data),
        .we         (ov7670_we),
        .wAddr      (ov7670_wAddr),
        .wData      (ov7670_wData)
    );

    Filter_Top U_Filter_TOP (
        .clk        (ov7670_pclk),
        .reset      (reset),
        .sel        (sel_final),
        .we_in      (ov7670_we),
        .wAddr_in   (ov7670_wAddr),
        .wData_in   (ov7670_wData),
        .btn_sticker(btn_sticker_final),
        .o_we_out   (o_we_out),
        .o_wAddr    (o_wAddr),
        .o_rData    (o_rData),
        .btn_left   (btn_left_final),
        .btn_right  (btn_right_final)
    );

    Frame_Buffer U_Frame_Buffer (
        .wclk (ov7670_pclk),
        .we   (o_we_out),
        .wAddr(o_wAddr),
        .wData(o_rData),
        .rclk (vga_pclk),
        .oe   (vga_den),
        .rAddr(vga_rAddr),
        .rData(vga_rData)
    );

    VGA_MemController U_VGA_MemController (
        .vga_sw (vga_sw_final),
        .DE     (vga_DE),
        .x_pixel(vga_x_pixel),
        .y_pixel(vga_y_pixel),
        .den    (vga_den),
        .rAddr  (vga_rAddr),
        .rData  (vga_rData),
        .r_port (r_port),
        .g_port (g_port),
        .b_port (b_port)
    );

    VGA_Decoder U_VGA_Decoder (
        .clk    (clk),
        .reset  (reset),
        .pclk   (vga_pclk),
        .h_sync (h_sync),
        .v_sync (v_sync),
        .x_pixel(vga_x_pixel),
        .y_pixel(vga_y_pixel),
        .DE     (vga_DE)
    );

endmodule
