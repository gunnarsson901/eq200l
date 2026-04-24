// frame_bram.v — 2048 × 8 synchronous RAM, inferred as iCE40 EBR.
//
// Both read and write are in one posedge-only always block (no async reset)
// so Yosys reliably maps this to 4 × SB_RAM40_4K blocks.
//
// Read latency: 1 clock cycle (rdata valid one cycle after raddr changes).
`timescale 1ns/1ps

module frame_bram (
    input  wire        clk,
    input  wire        we,
    input  wire [10:0] waddr,
    input  wire [7:0]  wdata,
    input  wire [10:0] raddr,
    output reg  [7:0]  rdata
);
    reg [7:0] mem [0:2047];

    always @(posedge clk) begin
        if (we)
            mem[waddr] <= wdata;
        rdata <= mem[raddr];
    end
endmodule
