// PHY Bridge – MITM forwarding and monitor mirroring.
//
// Operates in clk_sys domain. Async FIFOs at the boundary (in top.v)
// decouple this module from the individual PHY REF_CLK domains.
//
// Data flow:
//   P1 RX  ──►  [FIFO]  ──►  phy_bridge  ──►  [FIFO]  ──►  P2 TX
//   P2 RX  ──►  [FIFO]  ──►  phy_bridge  ──►  [FIFO]  ──►  P1 TX
//   Both directions are mirrored to P3 TX (monitor/Wireshark port).
//
// MITM hook:
//   When mitm_en = 1, the bridge inspects every forwarded byte.
//   If the byte index equals mitm_byte_idx and the byte value equals
//   mitm_match, it is replaced with mitm_replace before forwarding.
`timescale 1ns/1ps

module phy_bridge (
    input  wire        clk_sys,
    input  wire        rst_n,

    // --- P1 RX (from async FIFO, already in clk_sys domain) ---
    input  wire        p1_rx_valid,
    input  wire [7:0]  p1_rx_data,
    input  wire        p1_rx_sof,
    input  wire        p1_rx_eof,
    output wire        p1_rx_ready,   // pop FIFO

    // --- P2 RX ---
    input  wire        p2_rx_valid,
    input  wire [7:0]  p2_rx_data,
    input  wire        p2_rx_sof,
    input  wire        p2_rx_eof,
    output wire        p2_rx_ready,

    // --- P2 TX (P1→P2 forward, into async FIFO) ---
    output reg         p2_tx_valid,
    output reg  [7:0]  p2_tx_data,
    output reg         p2_tx_sof,
    output reg         p2_tx_eof,
    input  wire        p2_tx_ready,   // FIFO has space

    // --- P1 TX (P2→P1 forward) ---
    output reg         p1_tx_valid,
    output reg  [7:0]  p1_tx_data,
    output reg         p1_tx_sof,
    output reg         p1_tx_eof,
    input  wire        p1_tx_ready,

    // --- P3 TX (monitor mirror, round-robin arbitrated) ---
    output reg         p3_tx_valid,
    output reg  [7:0]  p3_tx_data,
    output reg         p3_tx_sof,
    output reg         p3_tx_eof,
    input  wire        p3_tx_ready,

    // --- Control registers (from smi_slave, CDC already applied) ---
    input  wire        mitm_en,
    input  wire [7:0]  mitm_byte_idx,
    input  wire [7:0]  mitm_match,
    input  wire [7:0]  mitm_replace,
    input  wire        sw_rst,         // software reset from Pi

    // --- Statistics (raw counters, read via smi_slave) ---
    output reg  [31:0] pkt_count_p1,   // frames from PHY1
    output reg  [31:0] pkt_count_p2    // frames from PHY2
);

    // ------------------------------------------------------------------
    // MITM byte substitution
    // ------------------------------------------------------------------
    reg [7:0] byte_idx_p1;  // byte index within current P1 frame
    reg [7:0] byte_idx_p2;

    function [7:0] mitm_check;
        input [7:0] data_in;
        input [7:0] idx;
        input        en;
        input [7:0]  ref_idx, ref_match, ref_replace;
        begin
            if (en && idx == ref_idx && data_in == ref_match)
                mitm_check = ref_replace;
            else
                mitm_check = data_in;
        end
    endfunction

    // ------------------------------------------------------------------
    // P1 → P2 + P3 mirror
    // ------------------------------------------------------------------
    // Simple pass-through: consume P1 when P2 FIFO has space.
    // For P3 we share the same data (fan-out, best-effort).
    assign p1_rx_ready = p1_rx_valid && p2_tx_ready;

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            p2_tx_valid  <= 0;
            p2_tx_data   <= 0;
            p2_tx_sof    <= 0;
            p2_tx_eof    <= 0;
            byte_idx_p1  <= 0;
            pkt_count_p1 <= 0;
        end else begin
            p2_tx_valid <= 0;
            p2_tx_sof   <= 0;
            p2_tx_eof   <= 0;

            if (sw_rst) begin
                byte_idx_p1  <= 0;
                pkt_count_p1 <= 0;
            end else if (p1_rx_valid && p2_tx_ready) begin
                p2_tx_valid <= 1;
                p2_tx_sof   <= p1_rx_sof;
                p2_tx_eof   <= p1_rx_eof;
                // SOF byte is always index 0; increment for next byte.
                p2_tx_data  <= mitm_check(p1_rx_data,
                                          p1_rx_sof ? 8'd0 : byte_idx_p1,
                                          mitm_en, mitm_byte_idx,
                                          mitm_match, mitm_replace);

                if (p1_rx_sof)
                    byte_idx_p1 <= 1;   // next byte will be index 1
                else
                    byte_idx_p1 <= byte_idx_p1 + 1;

                if (p1_rx_eof)
                    pkt_count_p1 <= pkt_count_p1 + 1;
            end
        end
    end

    // ------------------------------------------------------------------
    // P2 → P1 + P3 mirror
    // ------------------------------------------------------------------
    assign p2_rx_ready = p2_rx_valid && p1_tx_ready;

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            p1_tx_valid  <= 0;
            p1_tx_data   <= 0;
            p1_tx_sof    <= 0;
            p1_tx_eof    <= 0;
            byte_idx_p2  <= 0;
            pkt_count_p2 <= 0;
        end else begin
            p1_tx_valid <= 0;
            p1_tx_sof   <= 0;
            p1_tx_eof   <= 0;

            if (sw_rst) begin
                byte_idx_p2  <= 0;
                pkt_count_p2 <= 0;
            end else if (p2_rx_valid && p1_tx_ready) begin
                p1_tx_valid <= 1;
                p1_tx_sof   <= p2_rx_sof;
                p1_tx_eof   <= p2_rx_eof;
                p1_tx_data  <= mitm_check(p2_rx_data,
                                          p2_rx_sof ? 8'd0 : byte_idx_p2,
                                          mitm_en, mitm_byte_idx,
                                          mitm_match, mitm_replace);

                if (p2_rx_sof)
                    byte_idx_p2 <= 1;
                else
                    byte_idx_p2 <= byte_idx_p2 + 1;

                if (p2_rx_eof)
                    pkt_count_p2 <= pkt_count_p2 + 1;
            end
        end
    end

    // ------------------------------------------------------------------
    // P3 monitor port – round-robin arbitration between P1 and P2 data
    // Priority: P1 if both present, P2 otherwise.
    // NOTE: In a real design use a separate output FIFO per source to
    //       avoid dropping mirror traffic under load.
    // ------------------------------------------------------------------
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            p3_tx_valid <= 0;
            p3_tx_data  <= 0;
            p3_tx_sof   <= 0;
            p3_tx_eof   <= 0;
        end else begin
            p3_tx_valid <= 0;
            p3_tx_sof   <= 0;
            p3_tx_eof   <= 0;

            if (!sw_rst && p3_tx_ready) begin
                if (p1_rx_valid) begin
                    p3_tx_valid <= 1;
                    p3_tx_data  <= p1_rx_data;
                    p3_tx_sof   <= p1_rx_sof;
                    p3_tx_eof   <= p1_rx_eof;
                end else if (p2_rx_valid) begin
                    p3_tx_valid <= 1;
                    p3_tx_data  <= p2_rx_data;
                    p3_tx_sof   <= p2_rx_sof;
                    p3_tx_eof   <= p2_rx_eof;
                end
            end
        end
    end

endmodule
