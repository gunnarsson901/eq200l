// frame_tap.v — Dual-output frame store for transparent RMII tap.
//
// Receives a byte stream from rmii_rx, buffers one complete frame in BRAM,
// then flushes to TWO sync_fifo write ports simultaneously:
//   fwd_fifo : [len_h, len_l, data...]          for forwarding via rmii_tx
//   cap_fifo : [dir, len_h, len_l, data...]      for SPI capture to Pi
//
// DIR parameter: 8'h01 = A→B, 8'h02 = B→A
//
// Stalls in flush if either FIFO is full; drops incoming frame during flush.
`timescale 1ns/1ps

module frame_tap #(
    parameter [7:0] DIR = 8'h01
) (
    input  wire       clk,
    input  wire       rst_n,

    // From rmii_rx
    input  wire       rx_valid,
    input  wire [7:0] rx_data,
    input  wire       rx_eof,

    // Forward FIFO write port: [len_h, len_l, data...]
    output reg        fwd_wr_en,
    output reg  [7:0] fwd_wr_data,
    input  wire       fwd_full,

    // Capture FIFO write port: [dir, len_h, len_l, data...]
    output reg        cap_wr_en,
    output reg  [7:0] cap_wr_data,
    input  wire       cap_full
);
    // ── Frame BRAM (2048 × 8, 4 × SB_RAM40_4K) ───────────────────────────
    reg        bram_we;
    reg [10:0] bram_waddr;
    reg  [7:0] bram_wdata;
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

    // ── States ────────────────────────────────────────────────────────────
    localparam S_RECV      = 3'd0;
    localparam S_FLUSH_DIR = 3'd1;   // DIR → cap only
    localparam S_FLUSH_H   = 3'd2;   // len_h → both
    localparam S_FLUSH_L   = 3'd3;   // len_l → both; issue first BRAM read
    localparam S_FLUSH_RD  = 3'd4;   // 1-cycle BRAM read latency
    localparam S_FLUSH_DAT = 3'd5;   // stream data → both

    reg [2:0]  state;
    reg [10:0] fwr_ptr;   // bytes stored this frame
    reg [10:0] frd_ptr;   // flush read pointer

    wire both_rdy = !fwd_full && !cap_full;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_RECV;
            fwr_ptr     <= 0;
            frd_ptr     <= 0;
            fwd_wr_en   <= 0;
            fwd_wr_data <= 0;
            cap_wr_en   <= 0;
            cap_wr_data <= 0;
            bram_we     <= 0;
            bram_waddr  <= 0;
            bram_wdata  <= 0;
            bram_raddr  <= 0;
        end else begin
            fwd_wr_en <= 0;
            cap_wr_en <= 0;
            bram_we   <= 0;

            case (state)

                // ── Receive: store bytes to BRAM ──────────────────────────
                S_RECV: begin
                    if (rx_valid && !rx_eof) begin
                        bram_we    <= 1;
                        bram_waddr <= fwr_ptr;
                        bram_wdata <= rx_data;
                        fwr_ptr    <= fwr_ptr + 1'b1;
                    end
                    if (rx_eof)
                        state <= S_FLUSH_DIR;
                end

                // ── DIR byte → cap FIFO only ──────────────────────────────
                S_FLUSH_DIR: begin
                    if (!cap_full) begin
                        cap_wr_en   <= 1;
                        cap_wr_data <= DIR;
                        state       <= S_FLUSH_H;
                    end
                end

                // ── Length high byte → both FIFOs ─────────────────────────
                S_FLUSH_H: begin
                    if (both_rdy) begin
                        fwd_wr_en   <= 1;
                        fwd_wr_data <= {5'd0, fwr_ptr[10:8]};
                        cap_wr_en   <= 1;
                        cap_wr_data <= {5'd0, fwr_ptr[10:8]};
                        state       <= S_FLUSH_L;
                    end
                end

                // ── Length low byte → both FIFOs; issue first BRAM read ───
                S_FLUSH_L: begin
                    if (both_rdy) begin
                        fwd_wr_en   <= 1;
                        fwd_wr_data <= fwr_ptr[7:0];
                        cap_wr_en   <= 1;
                        cap_wr_data <= fwr_ptr[7:0];
                        bram_raddr  <= 0;
                        frd_ptr     <= 0;
                        state       <= S_FLUSH_RD;
                    end
                end

                // ── Wait 1 cycle for BRAM read latency ────────────────────
                S_FLUSH_RD: state <= S_FLUSH_DAT;

                // ── Stream BRAM data to both FIFOs ────────────────────────
                S_FLUSH_DAT: begin
                    if (both_rdy) begin
                        fwd_wr_en   <= 1;
                        fwd_wr_data <= bram_rdata;
                        cap_wr_en   <= 1;
                        cap_wr_data <= bram_rdata;
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
