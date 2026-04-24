// iCESugar-Pro Network Tap – Top Level
//
// Clock domains:
//   clk_p1  (50 MHz) – PHY1 REF_CLK, drives rmii_rx/tx for PHY1
//   clk_p2  (50 MHz) – PHY2 REF_CLK, drives rmii_rx/tx for PHY2
//   clk_p3  (50 MHz) – PHY3 REF_CLK, drives rmii_tx for monitor port
//   clk_sys (48 MHz) – internal PLL (12 MHz × 4), drives phy_bridge
//   clk_smi (var.)   – CM4 SMI clock, drives smi_slave
//
// Async FIFOs bridge every domain crossing.
`timescale 1ns/1ps

module top (
    input  wire        clk_12m,    // 12 MHz onboard oscillator

    // PHY1 (bridge side A)
    input  wire        p1_ref_clk,
    input  wire        p1_crs_dv,
    input  wire [1:0]  p1_rxd,
    output wire        p1_txen,
    output wire [1:0]  p1_txd,
    output wire        p1_rst_n,

    // PHY2 (bridge side B)
    input  wire        p2_ref_clk,
    input  wire        p2_crs_dv,
    input  wire [1:0]  p2_rxd,
    output wire        p2_txen,
    output wire [1:0]  p2_txd,
    output wire        p2_rst_n,

    // PHY3 (monitor / Wireshark port)
    input  wire        p3_ref_clk,
    input  wire        p3_crs_dv,
    input  wire [1:0]  p3_rxd,     // unused – monitor is TX-only
    output wire        p3_txen,
    output wire [1:0]  p3_txd,
    output wire        p3_rst_n,

    // SMI bus to CM4
    input  wire        smi_clk,
    inout  wire [7:0]  smi_d,      // bidirectional on real board
    input  wire [5:0]  smi_sa,
    input  wire        smi_soe_n,
    input  wire        smi_swe_n,

    // Debug LEDs
    output wire [2:0]  led
);

    // ------------------------------------------------------------------
    // PLL placeholder – replace with SB_PLL40_CORE for iCE40UP5K
    // In simulation clk_sys is driven directly by the testbench.
    // ------------------------------------------------------------------
    wire clk_sys = clk_12m;  // PLACEHOLDER – use PLL in synthesis
    wire rst_n_sys = 1'b1;   // PLACEHOLDER – tie to POR/reset logic

    // ------------------------------------------------------------------
    // PHY resets: keep low until stable (use proper reset sequencer)
    // ------------------------------------------------------------------
    assign p1_rst_n = rst_n_sys;
    assign p2_rst_n = rst_n_sys;
    assign p3_rst_n = rst_n_sys;

    // ==================================================================
    // PHY1 RX  →  bridge (clk_p1 → clk_sys via async FIFO)
    // ==================================================================
    wire        p1_rx_valid, p1_rx_sof, p1_rx_eof;
    wire [7:0]  p1_rx_data;

    rmii_rx phy_inst_1_rx (
        .clk     (p1_ref_clk),
        .rst_n   (rst_n_sys),
        .crs_dv  (p1_crs_dv),
        .rxd     (p1_rxd),
        .rx_valid(p1_rx_valid),
        .rx_data (p1_rx_data),
        .rx_sof  (p1_rx_sof),
        .rx_eof  (p1_rx_eof)
    );

    // Pack SOF/EOF into data bus for FIFO transport
    wire [9:0]  p1_fifo_wr_data = {p1_rx_sof, p1_rx_eof, p1_rx_data};
    wire        p1_fifo_wr_full;
    wire [9:0]  p1_fifo_rd_data;
    wire        p1_fifo_rd_empty;
    wire        p1_fifo_rd_en;

    async_fifo #(.DATA_W(10), .DEPTH(64), .ADDR_W(6)) fifo_p1_to_sys (
        .wr_clk  (p1_ref_clk),   .wr_rst_n(rst_n_sys),
        .wr_en   (p1_rx_valid && !p1_fifo_wr_full),
        .wr_data (p1_fifo_wr_data),
        .wr_full (p1_fifo_wr_full),
        .rd_clk  (clk_sys),      .rd_rst_n(rst_n_sys),
        .rd_en   (p1_fifo_rd_en),
        .rd_data (p1_fifo_rd_data),
        .rd_empty(p1_fifo_rd_empty)
    );

    wire br_p1_rx_valid = !p1_fifo_rd_empty;
    wire br_p1_rx_sof   = p1_fifo_rd_data[9];
    wire br_p1_rx_eof   = p1_fifo_rd_data[8];
    wire [7:0] br_p1_rx_data = p1_fifo_rd_data[7:0];

    // ==================================================================
    // PHY2 RX  →  bridge (clk_p2 → clk_sys)
    // ==================================================================
    wire        p2_rx_valid, p2_rx_sof, p2_rx_eof;
    wire [7:0]  p2_rx_data;

    rmii_rx phy_inst_2_rx (
        .clk     (p2_ref_clk),
        .rst_n   (rst_n_sys),
        .crs_dv  (p2_crs_dv),
        .rxd     (p2_rxd),
        .rx_valid(p2_rx_valid),
        .rx_data (p2_rx_data),
        .rx_sof  (p2_rx_sof),
        .rx_eof  (p2_rx_eof)
    );

    wire [9:0]  p2_fifo_wr_data = {p2_rx_sof, p2_rx_eof, p2_rx_data};
    wire        p2_fifo_wr_full;
    wire [9:0]  p2_fifo_rd_data;
    wire        p2_fifo_rd_empty;
    wire        p2_fifo_rd_en;

    async_fifo #(.DATA_W(10), .DEPTH(64), .ADDR_W(6)) fifo_p2_to_sys (
        .wr_clk  (p2_ref_clk),   .wr_rst_n(rst_n_sys),
        .wr_en   (p2_rx_valid && !p2_fifo_wr_full),
        .wr_data (p2_fifo_wr_data),
        .wr_full (p2_fifo_wr_full),
        .rd_clk  (clk_sys),      .rd_rst_n(rst_n_sys),
        .rd_en   (p2_fifo_rd_en),
        .rd_data (p2_fifo_rd_data),
        .rd_empty(p2_fifo_rd_empty)
    );

    wire br_p2_rx_valid = !p2_fifo_rd_empty;
    wire br_p2_rx_sof   = p2_fifo_rd_data[9];
    wire br_p2_rx_eof   = p2_fifo_rd_data[8];
    wire [7:0] br_p2_rx_data = p2_fifo_rd_data[7:0];

    // ==================================================================
    // SMI slave (clk_smi domain)
    // ==================================================================
    wire [7:0]  smi_d_out;
    wire        smi_d_oe;
    wire        smi_sw_rst_raw, smi_mitm_en_raw;
    wire [7:0]  smi_mitm_byte_idx_raw, smi_mitm_match_raw, smi_mitm_replace_raw;
    wire [31:0] br_pkt_count_p1, br_pkt_count_p2;

    assign smi_d = smi_d_oe ? smi_d_out : 8'hZZ;

    smi_slave smi_slave_inst (
        .clk_smi      (smi_clk),
        .rst_n        (rst_n_sys),
        .smi_sa       (smi_sa),
        .smi_d_in     (smi_d),
        .smi_d_out    (smi_d_out),
        .smi_d_oe     (smi_d_oe),
        .smi_soe_n    (smi_soe_n),
        .smi_swe_n    (smi_swe_n),
        .sw_rst       (smi_sw_rst_raw),
        .mitm_en      (smi_mitm_en_raw),
        .mitm_byte_idx(smi_mitm_byte_idx_raw),
        .mitm_match   (smi_mitm_match_raw),
        .mitm_replace (smi_mitm_replace_raw),
        .pkt_count_p1 (br_pkt_count_p1),
        .pkt_count_p2 (br_pkt_count_p2)
    );

    // CDC: smi_clk → clk_sys (control signals)
    wire mitm_en_sys, sw_rst_sys;
    cdc_sync #(.WIDTH(1)) cdc_mitm_en  (.clk_dst(clk_sys), .rst_n(rst_n_sys), .d(smi_mitm_en_raw),  .q(mitm_en_sys));
    cdc_sync #(.WIDTH(1)) cdc_sw_rst   (.clk_dst(clk_sys), .rst_n(rst_n_sys), .d(smi_sw_rst_raw),   .q(sw_rst_sys));

    // Multi-bit control: safe only if stable before use (designer responsibility)
    wire [7:0] mitm_byte_idx_sys, mitm_match_sys, mitm_replace_sys;
    cdc_sync #(.WIDTH(8)) cdc_mit_idx  (.clk_dst(clk_sys), .rst_n(rst_n_sys), .d(smi_mitm_byte_idx_raw), .q(mitm_byte_idx_sys));
    cdc_sync #(.WIDTH(8)) cdc_mit_mat  (.clk_dst(clk_sys), .rst_n(rst_n_sys), .d(smi_mitm_match_raw),    .q(mitm_match_sys));
    cdc_sync #(.WIDTH(8)) cdc_mit_rep  (.clk_dst(clk_sys), .rst_n(rst_n_sys), .d(smi_mitm_replace_raw),  .q(mitm_replace_sys));

    // ==================================================================
    // PHY Bridge (clk_sys domain)
    // ==================================================================
    wire br_p1_rx_ready, br_p2_rx_ready;
    wire br_p2_tx_valid; wire [7:0] br_p2_tx_data; wire br_p2_tx_sof, br_p2_tx_eof;
    wire br_p1_tx_valid; wire [7:0] br_p1_tx_data; wire br_p1_tx_sof, br_p1_tx_eof;
    wire br_p3_tx_valid; wire [7:0] br_p3_tx_data; wire br_p3_tx_sof, br_p3_tx_eof;

    assign p1_fifo_rd_en = br_p1_rx_ready;
    assign p2_fifo_rd_en = br_p2_rx_ready;

    phy_bridge phy_bridge_inst (
        .clk_sys      (clk_sys),
        .rst_n        (rst_n_sys),

        .p1_rx_valid  (br_p1_rx_valid), .p1_rx_data(br_p1_rx_data),
        .p1_rx_sof    (br_p1_rx_sof),   .p1_rx_eof (br_p1_rx_eof),
        .p1_rx_ready  (br_p1_rx_ready),

        .p2_rx_valid  (br_p2_rx_valid), .p2_rx_data(br_p2_rx_data),
        .p2_rx_sof    (br_p2_rx_sof),   .p2_rx_eof (br_p2_rx_eof),
        .p2_rx_ready  (br_p2_rx_ready),

        .p2_tx_valid  (br_p2_tx_valid), .p2_tx_data(br_p2_tx_data),
        .p2_tx_sof    (br_p2_tx_sof),   .p2_tx_eof (br_p2_tx_eof),
        .p2_tx_ready  (1'b1),           // assume output FIFO always ready

        .p1_tx_valid  (br_p1_tx_valid), .p1_tx_data(br_p1_tx_data),
        .p1_tx_sof    (br_p1_tx_sof),   .p1_tx_eof (br_p1_tx_eof),
        .p1_tx_ready  (1'b1),

        .p3_tx_valid  (br_p3_tx_valid), .p3_tx_data(br_p3_tx_data),
        .p3_tx_sof    (br_p3_tx_sof),   .p3_tx_eof (br_p3_tx_eof),
        .p3_tx_ready  (1'b1),

        .mitm_en      (mitm_en_sys),
        .mitm_byte_idx(mitm_byte_idx_sys),
        .mitm_match   (mitm_match_sys),
        .mitm_replace (mitm_replace_sys),
        .sw_rst       (sw_rst_sys),

        .pkt_count_p1 (br_pkt_count_p1),
        .pkt_count_p2 (br_pkt_count_p2)
    );

    // ==================================================================
    // PHY1 TX  (clk_sys data → clk_p1 domain via async FIFO → rmii_tx)
    // ==================================================================
    // (Symmetric structure to PHY1-RX path – omitted for brevity)
    // TODO: add async_fifo + rmii_tx for P1_TX, P2_TX, P3_TX

    // Stub outputs to suppress undriven warnings during initial sim
    assign p1_txen = 0; assign p1_txd = 0;
    assign p2_txen = 0; assign p2_txd = 0;
    assign p3_txen = 0; assign p3_txd = 0;

    // ==================================================================
    // Debug LEDs
    // ==================================================================
    assign led[0] = br_p1_rx_valid;   // activity on P1
    assign led[1] = br_p2_rx_valid;   // activity on P2
    assign led[2] = mitm_en_sys;      // MITM mode active

endmodule
