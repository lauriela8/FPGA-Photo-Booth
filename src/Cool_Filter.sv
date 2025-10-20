`timescale 1ns / 1ps

module Cool_Filter #(
    parameter int IMG_WIDTH  = 320,
    parameter int IMG_HEIGHT = 240
) (
    input logic clk,
    input logic reset,
    // input stream
    input logic we_in,
    input logic [$clog2(IMG_WIDTH*IMG_HEIGHT)-1:0] wAddr_in,
    input logic [15:0] wData_in,
    // output stream
    output logic we_out,
    output logic [$clog2(IMG_WIDTH*IMG_HEIGHT)-1:0] wAddr_out,
    output logic [15:0] wData_out
);

    logic [4:0] r_in;
    logic [5:0] g_in;
    logic [4:0] b_in;

    logic [4:0] r_cool;
    logic [5:0] g_cool;
    logic [4:0] b_cool;

    always_comb begin
        r_in   = wData_in[15:11];
        g_in   = wData_in[10:5];
        b_in   = wData_in[4:0];

        b_cool = (b_in + 2 > 31) ? 5'd31 : (b_in + 2);
        r_cool = (r_in > 2) ? (r_in - 2) : 5'd0;
        g_cool = g_in;
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            we_out    <= 1'b0;
            wAddr_out <= '0;
            wData_out <= '0;
        end else begin
            we_out    <= we_in;
            wAddr_out <= wAddr_in;
            wData_out <= {r_cool, g_cool, b_cool};
        end
    end
endmodule
