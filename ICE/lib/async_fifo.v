// Asynchronous FIFO using Gray-code pointers.
// Safe for crossing between two unrelated clock domains.
//
// Parameters:
//   DATA_W – data width (default 8)
//   DEPTH  – number of entries, must be a power of 2 (default 16)
//   ADDR_W – log2(DEPTH) (default 4)
`timescale 1ns/1ps

module async_fifo #(
    parameter DATA_W = 8,
    parameter DEPTH  = 16,
    parameter ADDR_W = 4
) (
    // Write port
    input  wire              wr_clk,
    input  wire              wr_rst_n,
    input  wire              wr_en,
    input  wire [DATA_W-1:0] wr_data,
    output wire              wr_full,

    // Read port
    input  wire              rd_clk,
    input  wire              rd_rst_n,
    input  wire              rd_en,
    output wire [DATA_W-1:0] rd_data,
    output wire              rd_empty
);

    // Storage
    reg [DATA_W-1:0] mem [0:DEPTH-1];

    // Binary pointers (one extra bit for full/empty disambiguation)
    reg [ADDR_W:0] wr_bin;
    reg [ADDR_W:0] rd_bin;

    // Gray-code versions
    wire [ADDR_W:0] wr_gray = wr_bin ^ (wr_bin >> 1);
    wire [ADDR_W:0] rd_gray = rd_bin ^ (rd_bin >> 1);

    // Sync rd_gray into write domain
    reg [ADDR_W:0] rd_gray_s1, rd_gray_s2;
    // Sync wr_gray into read domain
    reg [ADDR_W:0] wr_gray_s1, wr_gray_s2;

    // ------------------------------------------------------------------
    // Write side
    // ------------------------------------------------------------------
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_bin     <= 0;
            rd_gray_s1 <= 0;
            rd_gray_s2 <= 0;
        end else begin
            {rd_gray_s2, rd_gray_s1} <= {rd_gray_s1, rd_gray};
            if (wr_en && !wr_full) begin
                mem[wr_bin[ADDR_W-1:0]] <= wr_data;
                wr_bin <= wr_bin + 1;
            end
        end
    end

    // Full: pointers have wrapped once relative to each other.
    // Gray-code full condition: MSB and MSB-1 differ, rest equal.
    assign wr_full = (wr_gray ==
                      {~rd_gray_s2[ADDR_W:ADDR_W-1], rd_gray_s2[ADDR_W-2:0]});

    // ------------------------------------------------------------------
    // Read side
    // ------------------------------------------------------------------
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_bin     <= 0;
            wr_gray_s1 <= 0;
            wr_gray_s2 <= 0;
        end else begin
            {wr_gray_s2, wr_gray_s1} <= {wr_gray_s1, wr_gray};
            if (rd_en && !rd_empty)
                rd_bin <= rd_bin + 1;
        end
    end

    assign rd_empty = (rd_gray == wr_gray_s2);
    assign rd_data  = mem[rd_bin[ADDR_W-1:0]];

endmodule
