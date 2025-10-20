`timescale 1ns / 1ps

module Filter_Top (
    input  logic        clk,
    input  logic        reset,
    input  logic [ 3:0] sel,
    input  logic        btn_sticker,
    input  logic        btn_left,
    input  logic        btn_right,
    // camera write stream
    input  logic        we_in,
    input  logic [16:0] wAddr_in,
    input  logic [15:0] wData_in,
    // to frame buffer
    output logic        o_we_out,
    output logic [16:0] o_wAddr,
    output logic [15:0] o_rData
);

    localparam int N = 16;
    logic            we       [N];
    logic [    16:0] addr     [N];
    logic [    15:0] data     [N];
    logic [   N-1:0] we_bus;
    logic [N*17-1:0] addr_bus;
    logic [N*16-1:0] data_bus;

    genvar i;
    generate
        for (i = 0; i < N; i++) begin
            assign we_bus[i]          = we[i];
            assign addr_bus[i*17+:17] = addr[i];
            assign data_bus[i*16+:16] = data[i];
        end
    endgenerate

    // 0: BYPASS
    assign we[0]   = we_in;
    assign addr[0] = wAddr_in;
    assign data[0] = wData_in;

    // 1: Gaussian
    Gaussian_Filter #(
        .IMG_WIDTH (320),
        .IMG_HEIGHT(240)
    ) U_Gaussian_Filter (
        .clk      (clk),
        .reset    (reset),
        .we_in    (we_in),
        .wAddr_in (wAddr_in),
        .wData_in (wData_in),
        .we_out   (we[1]),
        .wAddr_out(addr[1]),
        .wData_out(data[1])
    );

    // 2: Sobel
    Sobel_Filter #(
        .IMG_WIDTH (320),
        .IMG_HEIGHT(240),
        .THRESHOLD (15)
    ) U_Sobel_Filter (
        .clk      (clk),
        .reset    (reset),
        .we_in    (we_in),
        .wAddr_in (wAddr_in),
        .wData_in (wData_in),
        .we_out   (we[2]),
        .wAddr_out(addr[2]),
        .wData_out(data[2])
    );

    // 3: Graduation
    Graduation_Filter #(
        .IMG_WIDTH    (320),
        .IMG_HEIGHT   (240),
        .SCALE_NUM    (3),
        .SCALE_DEN    (2),
        .TOP_MARGIN   (6),
        .BOTTOM_MARGIN(6),
        .MID_GAP      (8),
        .TEXT_COLOR   (16'hFFFF)
    ) U_Graduation_Filter (
        .clk      (clk),
        .reset    (reset),
        .we_in    (we_in),
        .wAddr_in (wAddr_in),
        .wData_in (wData_in),
        .we_out   (we[3]),
        .wAddr_out(addr[3]),
        .wData_out(data[3])
    );

    // 4: Warm
    Warm_Filter #(
        .IMG_WIDTH (320),
        .IMG_HEIGHT(240)
    ) U_Warm_Filter (
        .clk      (clk),
        .reset    (reset),
        .we_in    (we_in),
        .wAddr_in (wAddr_in),
        .wData_in (wData_in),
        .we_out   (we[4]),
        .wAddr_out(addr[4]),
        .wData_out(data[4])
    );

    // 5: Cool
    Cool_Filter #(
        .IMG_WIDTH (320),
        .IMG_HEIGHT(240)
    ) U_Cool_Filter (
        .clk      (clk),
        .reset    (reset),
        .we_in    (we_in),
        .wAddr_in (wAddr_in),
        .wData_in (wData_in),
        .we_out   (we[5]),
        .wAddr_out(addr[5]),
        .wData_out(data[5])
    );

    // 6: Ghost
    Ghost_Filter #(
        .IMG_WIDTH (320),
        .IMG_HEIGHT(240)
    ) U_Ghost_Filter (
        .clk      (clk),
        .reset    (reset),
        .we_in    (we_in),
        .wAddr_in (wAddr_in),
        .wData_in (wData_in),
        .we_out   (we[6]),
        .wAddr_out(addr[6]),
        .wData_out(data[6])
    );

    // 7: Cartoon
    Cartoon_Filter #(
        .IMG_WIDTH (320),
        .IMG_HEIGHT(240)
    ) U_Cartoon_Filter (
        .clk      (clk),
        .reset    (reset),
        .we_in    (we_in),
        .wAddr_in (wAddr_in),
        .wData_in (wData_in),
        .we_out   (we[7]),
        .wAddr_out(addr[7]),
        .wData_out(data[7])
    );

    // 8: PopArt
    PopArt_Filter #(
        .IMG_WIDTH   (320),
        .IMG_HEIGHT  (240),
        .KEEP_RB_MSBS(2),
        .KEEP_G_MSBS (2),
        .EDGE_THR    (50)
    ) U_PopArt_Filter (
        .clk      (clk),
        .reset    (reset),
        .we_in    (we_in),
        .wAddr_in (wAddr_in),
        .wData_in (wData_in),
        .we_out   (we[8]),
        .wAddr_out(addr[8]),
        .wData_out(data[8])
    );

    // 9: Mirror
    Mirror_Filter #(
        .IMG_WIDTH (320),
        .IMG_HEIGHT(240),
        .MODE      (2)
    ) U_Mirror_Filter (
        .clk      (clk),
        .reset    (reset),
        .we_in    (we_in),
        .wAddr_in (wAddr_in),
        .wData_in (wData_in),
        .we_out   (we[9]),
        .wAddr_out(addr[9]),
        .wData_out(data[9])
    );

    // 10: Sticker
    Sticker_Filter #(
        .IMG_WIDTH       (320),
        .IMG_HEIGHT      (240),
        .RED_SEQUENCE_MIN(8),
        .BOX_SIZE        (80)
    ) U_Sticker_Filter (
        .clk        (clk),
        .reset      (reset),
        .we_in      (we_in),
        .wAddr_in   (wAddr_in),
        .wData_in   (wData_in),
        .btn_sticker(btn_sticker),
        .btn_left   (btn_left),
        .btn_right  (btn_right),
        .we_out     (we[10]),
        .wAddr_out  (addr[10]),
        .wData_out  (data[10])
    );

    genvar k;
    generate
        for (k = 1; k < N; k++) begin
            if (k != 1 && k != 2 && k != 3 && k != 4 && k != 5 && k != 6 && k != 7 && k != 8 && k != 9 && k != 10) begin
                assign we[k]   = we[0];
                assign addr[k] = addr[0];
                assign data[k] = data[0];
            end
        end
    endgenerate

    logic        we_sel;
    logic [16:0] wAddr_sel;
    logic [15:0] rData_sel;
    logic        we_sharpen;
    logic [16:0] wAddr_sharpen;
    logic [15:0] rData_sharpen;

    filter_selector #(
        .N(N)
    ) U_SEL (
        .sel      (sel),
        .we_bus   (we_bus),
        .addr_bus (addr_bus),
        .data_bus (data_bus),
        .we_out   (we_sel),
        .wAddr_out(wAddr_sel),
        .wData_out(rData_sel)
    );

    Sharpen_Filter #(
        .IMG_WIDTH (320),
        .IMG_HEIGHT(240)
    ) U_Sharpen_Filter (
        .clk      (clk),
        .reset    (reset),
        .we_in    (we_sel),
        .wAddr_in (wAddr_sel),
        .wData_in (rData_sel),
        .we_out   (we_sharpen),
        .wAddr_out(wAddr_sharpen),
        .wData_out(rData_sharpen)
    );

    sharpen_mux U_sharpen_mux (
        .sel           (sel),
        .we_original   (we_sel),
        .wAddr_original(wAddr_sel),
        .wData_original(rData_sel),
        .we_sharpen    (we_sharpen),
        .wAddr_sharpen (wAddr_sharpen),
        .wData_sharpen (rData_sharpen),
        .we_out        (o_we_out),
        .wAddr_out     (o_wAddr),
        .wData_out     (o_rData)
    );

endmodule

module filter_selector #(
    parameter int N = 16
) (
    input  logic [     3:0] sel,
    input  logic [   N-1:0] we_bus,
    input  logic [N*17-1:0] addr_bus,
    input  logic [N*16-1:0] data_bus,
    output logic            we_out,
    output logic [    16:0] wAddr_out,
    output logic [    15:0] wData_out
);
    assign we_out    = we_bus[sel];
    assign wAddr_out = addr_bus[sel*17+:17];
    assign wData_out = data_bus[sel*16+:16];

endmodule

module sharpen_mux (
    input  logic [ 3:0] sel,
    input  logic        we_original,
    input  logic [16:0] wAddr_original,
    input  logic [15:0] wData_original,
    input  logic        we_sharpen,
    input  logic [16:0] wAddr_sharpen,
    input  logic [15:0] wData_sharpen,
    output logic        we_out,
    output logic [16:0] wAddr_out,
    output logic [15:0] wData_out
);
    always_comb begin
        we_out    = we_sharpen;
        wAddr_out = wAddr_sharpen;
        wData_out = wData_sharpen;
        case (sel)
            4'b0001: begin  // 1: Gaussian
                we_out = we_original;
                wAddr_out = wAddr_original;
                wData_out = wData_original;
            end
            4'b0010: begin  // 2: Sobel
                we_out = we_original;
                wAddr_out = wAddr_original;
                wData_out = wData_original;
            end
            4'b0111: begin  // 7: Cartoon
                we_out = we_original;
                wAddr_out = wAddr_original;
                wData_out = wData_original;
            end
            4'b1000: begin  // 8: PopArt
                we_out = we_original;
                wAddr_out = wAddr_original;
                wData_out = wData_original;
            end
            4'b1010: begin  // Sticker
                we_out = we_original;
                wAddr_out = wAddr_original;
                wData_out = wData_original;
            end
        endcase
    end
endmodule
