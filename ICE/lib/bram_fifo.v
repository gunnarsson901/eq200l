// bram_fifo.v — FWFT FIFO backed by synchronous block RAM.
//
// Provides zero-latency read (rd_data valid when !rd_empty) while using
// synchronous reads internally so Yosys infers SB_RAM40_4K EBR on iCE40.
// A 1-entry output register bridges the 1-cycle BRAM read latency.
//
// DEPTH must be a power of 2.  Resource use: DEPTH×DATA_W bits of EBR.
// For iCE40HX8K (32 × SB_RAM40_4K = 16 KB):
//   DEPTH=2048,DATA_W=8 → 4 EBR blocks
//   DEPTH=4096,DATA_W=8 → 8 EBR blocks
`timescale 1ns/1ps

module bram_fifo #(
    parameter DATA_W = 8,
    parameter DEPTH  = 2048,
    parameter ADDR_W = 11     // must equal log2(DEPTH)
) (
    input  wire              clk,
    input  wire              rst_n,
    // Write port
    input  wire              wr_en,
    input  wire [DATA_W-1:0] wr_data,
    output wire              wr_full,
    // Read port (FWFT — rd_data valid whenever !rd_empty)
    input  wire              rd_en,
    output wire [DATA_W-1:0] rd_data,
    output wire              rd_empty
);
    // ── Block RAM (synchronous read + write; no async reset = EBR inference) ──
    reg [DATA_W-1:0] mem [0:DEPTH-1];
    reg [DATA_W-1:0] bram_q;

    always @(posedge clk) begin
        if (wr_en && !wr_full)
            mem[wr_ptr[ADDR_W-1:0]] <= wr_data;
        bram_q <= mem[fetch_ptr[ADDR_W-1:0]];   // synchronous pre-read
    end

    // ── Pointers ──────────────────────────────────────────────────────────
    reg [ADDR_W:0] wr_ptr;      // write pointer (extra MSB for full/empty)
    reg [ADDR_W:0] fetch_ptr;   // next BRAM read address

    // Items written but not yet fetched into output register
    wire [ADDR_W:0] in_bram = wr_ptr - fetch_ptr;

    // ── Output register ───────────────────────────────────────────────────
    reg [DATA_W-1:0] out_reg;
    reg              out_valid;
    reg              fetch_pend;   // BRAM read in flight; result arrives next cycle

    assign rd_data  = out_reg;
    assign rd_empty = !out_valid;

    // Total items = in BRAM + in flight + in output reg
    wire [ADDR_W:0] total = in_bram
                          + {{ADDR_W{1'b0}}, fetch_pend}
                          + {{ADDR_W{1'b0}}, out_valid};
    assign wr_full = (total >= DEPTH[ADDR_W:0]);

    // ── Control signals ───────────────────────────────────────────────────
    wire do_wr  = wr_en && !wr_full;
    wire do_rd  = rd_en && out_valid;

    // Issue fetch when output register will be empty next cycle.
    // Using next-state out_valid eliminates a 1-cycle bubble after each read.
    wire out_valid_nx = fetch_pend ? 1'b1
                      : (do_rd    ? 1'b0 : out_valid);
    wire do_fetch = !out_valid_nx && !fetch_pend && (in_bram != 0);

    // ── Sequential logic ──────────────────────────────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr     <= 0;
            fetch_ptr  <= 0;
            out_valid  <= 0;
            fetch_pend <= 0;
            out_reg    <= 0;
        end else begin
            // Write
            if (do_wr) wr_ptr <= wr_ptr + 1'b1;

            // Issue BRAM fetch (bram_q will hold mem[fetch_ptr] next cycle)
            if (do_fetch) begin
                fetch_ptr  <= fetch_ptr + 1'b1;
                fetch_pend <= 1'b1;
            end

            // Collect BRAM result into output register
            // (fetch_pend=1 implies out_valid=0, so no conflict with do_rd)
            if (fetch_pend) begin
                out_reg    <= bram_q;
                out_valid  <= 1'b1;
                fetch_pend <= 1'b0;
            end

            // User read — clears output register
            // (do_rd=1 implies out_valid=1, so no conflict with collection)
            if (do_rd) out_valid <= 1'b0;
        end
    end
endmodule
