// frame_store.v — Buffer one Ethernet frame; write (len_h, len_l, data…) to FIFO.
//
// Uses frame_bram (a dedicated submodule) for the 2048×8 frame buffer so that
// Yosys reliably infers it as 4 × SB_RAM40_4K EBR.  Read latency is 1 clock;
// S_FLUSH_RD waits one cycle after updating raddr before reading rdata.
//
// rx_eof from rmii_rx is always a duplicate of the last valid byte (the
// crs_dv de-assertion cycle re-clocks the same sreg).  We skip it so the
// stored frame length is correct.
//
// Frames that arrive during a flush are silently dropped — fine for a tap.
`timescale 1ns/1ps

module frame_store (
    input  wire       clk,
    input  wire       rst_n,

    // From rmii_rx
    input  wire       rx_valid,
    input  wire [7:0] rx_data,
    input  wire       rx_eof,

    // To sync_fifo (write port)
    output reg        fifo_wr_en,
    output reg  [7:0] fifo_wr_data,
    input  wire       fifo_full
);
    // ── Frame BRAM (2048 × 8, 4 EBR blocks) ─────────────────────────────────
    reg        bram_we;
    reg [10:0] bram_waddr;
    reg [7:0]  bram_wdata;
    reg [10:0] bram_raddr;
    wire [7:0] bram_rdata;

    frame_bram bram_inst (
        .clk   (clk),
        .we    (bram_we),
        .waddr (bram_waddr),
        .wdata (bram_wdata),
        .raddr (bram_raddr),
        .rdata (bram_rdata)
    );

    // ── State machine ────────────────────────────────────────────────────────
    localparam S_RECV      = 3'd0;
    localparam S_FLUSH_H   = 3'd1;
    localparam S_FLUSH_L   = 3'd2;
    localparam S_FLUSH_RD  = 3'd3;   // wait 1 cycle for BRAM read latency
    localparam S_FLUSH_DAT = 3'd4;

    reg [2:0]  state;
    reg [10:0] fwr_ptr;   // bytes stored this frame
    reg [10:0] frd_ptr;   // flush read pointer

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_RECV;
            fwr_ptr      <= 0;
            frd_ptr      <= 0;
            fifo_wr_en   <= 0;
            fifo_wr_data <= 0;
            bram_we      <= 0;
            bram_waddr   <= 0;
            bram_wdata   <= 0;
            bram_raddr   <= 0;
        end else begin
            fifo_wr_en <= 0;
            bram_we    <= 0;

            case (state)
                // ── Receive ────────────────────────────────────────────────
                S_RECV: begin
                    if (rx_valid && !rx_eof) begin
                        bram_we    <= 1;
                        bram_waddr <= fwr_ptr;
                        bram_wdata <= rx_data;
                        fwr_ptr    <= fwr_ptr + 1'b1;
                    end
                    if (rx_eof) begin
                        state   <= S_FLUSH_H;
                        frd_ptr <= 0;
                    end
                end

                // ── Flush: length high byte ────────────────────────────────
                S_FLUSH_H: begin
                    if (!fifo_full) begin
                        fifo_wr_en   <= 1;
                        fifo_wr_data <= {5'd0, fwr_ptr[10:8]};
                        state        <= S_FLUSH_L;
                    end
                end

                // ── Flush: length low byte ─────────────────────────────────
                S_FLUSH_L: begin
                    if (!fifo_full) begin
                        fifo_wr_en   <= 1;
                        fifo_wr_data <= fwr_ptr[7:0];
                        // Issue first BRAM read (addr 0); data ready next cycle
                        bram_raddr <= 0;
                        frd_ptr    <= 0;
                        state      <= S_FLUSH_RD;
                    end
                end

                // ── Wait one cycle for BRAM read latency ───────────────────
                S_FLUSH_RD: begin
                    state <= S_FLUSH_DAT;
                end

                // ── Flush: stream bytes from BRAM to FIFO ─────────────────
                S_FLUSH_DAT: begin
                    if (!fifo_full) begin
                        fifo_wr_en   <= 1;
                        fifo_wr_data <= bram_rdata;
                        if (frd_ptr == fwr_ptr - 1'b1) begin
                            state   <= S_RECV;
                            fwr_ptr <= 0;
                        end else begin
                            frd_ptr    <= frd_ptr + 1'b1;
                            bram_raddr <= frd_ptr + 1'b1;
                            state      <= S_FLUSH_RD;
                        end
                    end
                end
            endcase
        end
    end
endmodule
