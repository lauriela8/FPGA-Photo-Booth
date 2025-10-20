`timescale 1ns / 1ps

module VGA_MemController (
    input  logic [ 1:0] vga_sw,
    // VGA side
    input  logic        DE,
    input  logic [ 9:0] x_pixel,
    input  logic [ 9:0] y_pixel,
    // frame buffer side
    output logic        den,
    output logic [16:0] rAddr,
    input  logic [15:0] rData,
    // export side
    output logic [ 3:0] r_port,
    output logic [ 3:0] g_port,
    output logic [ 3:0] b_port
);
    logic        den_original;
    logic [16:0] rAddr_original;
    logic [ 3:0] r_port_original;
    logic [ 3:0] g_port_original;
    logic [ 3:0] b_port_original;

    logic        den_fullscreen;
    logic [16:0] rAddr_fullscreen;
    logic [ 3:0] r_port_fullscreen;
    logic [ 3:0] g_port_fullscreen;
    logic [ 3:0] b_port_fullscreen;

    logic        den_splitscreen;
    logic [16:0] rAddr_splitscreen;
    logic [ 3:0] r_port_splitscreen;
    logic [ 3:0] g_port_splitscreen;
    logic [ 3:0] b_port_splitscreen;

    VGA_MemController_Original U_VGA_MemController_Original (
        .*,
        .den   (den_original),
        .rAddr(rAddr_original),
        .r_port(r_port_original),
        .g_port(g_port_original),
        .b_port(b_port_original)
    );
    VGA_MemController_FullScreen U_VGA_MemController_FullScreen (
        .*,
        .den   (den_fullscreen),
        .rAddr (rAddr_fullscreen),
        .r_port(r_port_fullscreen),
        .g_port(g_port_fullscreen),
        .b_port(b_port_fullscreen)
    );
    VGA_MemController_SplitScreen U_VGA_MemController_SplitScreen (
        .*,
        .den   (den_splitscreen),
        .rAddr (rAddr_splitscreen),
        .r_port(r_port_splitscreen),
        .g_port(g_port_splitscreen),
        .b_port(b_port_splitscreen)
    );
    vga_mux U_VGA_MUX (
        .*,
        .den_out(den),
        .rAddr_out(rAddr),
        .r_port_out(r_port),
        .g_port_out(g_port),
        .b_port_out(b_port)
    );

endmodule

// Original
module VGA_MemController_Original (
    // VGA side
    input  logic        DE,
    input  logic [ 9:0] x_pixel,
    input  logic [ 9:0] y_pixel,
    // frame buffer side
    output logic        den,
    output logic [16:0] rAddr,
    input  logic [15:0] rData,
    // export side
    output logic [ 3:0] r_port,
    output logic [ 3:0] g_port,
    output logic [ 3:0] b_port
);

    assign den = DE && x_pixel < 320 && y_pixel < 240;
    assign rAddr = den ? (y_pixel * 320 + x_pixel) : 17'bz;
    assign {r_port, g_port, b_port} = den ? {rData[15:12], rData[10:7], rData[4:1]} : 12'b0;

endmodule

// FullScreen
module VGA_MemController_FullScreen #(
    parameter int IMG_W = 320,
    parameter int IMG_H = 240
) (
    // VGA side
    input  logic        DE,
    input  logic [ 9:0] x_pixel,
    input  logic [ 9:0] y_pixel,
    // frame buffer side
    output logic        den,
    output logic [16:0] rAddr,
    input  logic [15:0] rData,
    // export side
    output logic [ 3:0] r_port,
    output logic [ 3:0] g_port,
    output logic [ 3:0] b_port
);

    localparam int OUT_W = IMG_W * 2;  // 640
    localparam int OUT_H = IMG_H * 2;  // 480

    wire in_active = (x_pixel < OUT_W) && (y_pixel < OUT_H);
    assign den = DE && in_active;

    wire [8:0] src_x = x_pixel[9:1];  // >>1
    wire [7:0] src_y = y_pixel[8:1];  // >>1

    wire [16:0] base = ({9'd0, src_y} << 8)  // *256
    + ({11'd0, src_y} << 6);  // *64
    assign rAddr = den ? (base + src_x) : 17'd0;

    wire [3:0] R4 = rData[15:12];
    wire [3:0] G4 = rData[10:7];
    wire [3:0] B4 = rData[4:1];

    assign {r_port, g_port, b_port} = den ? {R4, G4, B4} : 12'h000;

endmodule

// 4 SplitScreen
module VGA_MemController_SplitScreen #(
    parameter int IMG_W = 320,
    parameter int IMG_H = 240
) (
    // VGA scan (0..639, 0..479)
    input  logic        DE,
    input  logic [ 9:0] x_pixel,
    input  logic [ 9:0] y_pixel,
    // frame buffer
    output logic        den,
    output logic [16:0] rAddr,
    input  logic [15:0] rData,
    // RGB444 out
    output logic [ 3:0] r_port,
    output logic [ 3:0] g_port,
    output logic [ 3:0] b_port
);

    localparam int ACT_W = IMG_W * 2;  // 640
    localparam int ACT_H = IMG_H * 2;  // 480

    wire in_active = (x_pixel < ACT_W) && (y_pixel < ACT_H);
    assign den = DE && in_active;

    // ------------------------------------------------------------
    // 2x2 타일링: (x % 320, y % 240)
    //  - 모듈로(%) 대신 단순 비교/감산과 "폭으로 잘라지게" 대입
    //  - src_x(9b), src_y(8b) 에 대입할 때 자동으로 하위비트만 남음
    // ------------------------------------------------------------
    logic [8:0] src_x;  // 0..319
    logic [7:0] src_y;  // 0..239

    always_comb begin
        // x mod 320
        if (x_pixel < IMG_W) src_x = x_pixel[8:0];  // 0..319
        else src_x = (x_pixel - IMG_W);

        // y mod 240
        if (y_pixel < IMG_H) src_y = y_pixel[7:0];  // 0..239
        else src_y = (y_pixel - IMG_H);
    end

    assign rAddr = (den) ? (src_y * IMG_W + src_x) : 17'd0;

    wire [3:0] R4 = rData[15:12];
    wire [3:0] G4 = rData[10:7];
    wire [3:0] B4 = rData[4:1];

    assign {r_port, g_port, b_port} = (den) ? {R4, G4, B4} : 12'h000;

endmodule

module vga_mux (
    input logic [1:0] vga_sw,

    input logic        den_original,
    input logic [16:0] rAddr_original,
    input logic [ 3:0] r_port_original,
    input logic [ 3:0] g_port_original,
    input logic [ 3:0] b_port_original,

    input logic        den_fullscreen,
    input logic [16:0] rAddr_fullscreen,
    input logic [ 3:0] r_port_fullscreen,
    input logic [ 3:0] g_port_fullscreen,
    input logic [ 3:0] b_port_fullscreen,

    input logic        den_splitscreen,
    input logic [16:0] rAddr_splitscreen,
    input logic [ 3:0] r_port_splitscreen,
    input logic [ 3:0] g_port_splitscreen,
    input logic [ 3:0] b_port_splitscreen,

    output logic        den_out,
    output logic [16:0] rAddr_out,
    output logic [ 3:0] r_port_out,
    output logic [ 3:0] g_port_out,
    output logic [ 3:0] b_port_out
);

    always_comb begin
        den_out    = 0;
        rAddr_out  = 0;
        r_port_out = 0;
        g_port_out = 0;
        b_port_out = 0;
        case (vga_sw)
            2'b00: begin
                den_out    = den_original;
                rAddr_out  = rAddr_original;
                r_port_out = r_port_original;
                g_port_out = g_port_original;
                b_port_out = b_port_original;
            end
            2'b01: begin
                den_out    = den_fullscreen;
                rAddr_out  = rAddr_fullscreen;
                r_port_out = r_port_fullscreen;
                g_port_out = g_port_fullscreen;
                b_port_out = b_port_fullscreen;
            end
            2'b10: begin
                den_out    = den_splitscreen;
                rAddr_out  = rAddr_splitscreen;
                r_port_out = r_port_splitscreen;
                g_port_out = g_port_splitscreen;
                b_port_out = b_port_splitscreen;
            end
        endcase
    end
endmodule
