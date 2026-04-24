// eq200l — Dual-port transparent RMII Ethernet tap.
//
// Port A (router/switch side):
//   PIO3_07=MDC  PIO3_08=CRS  PIO3_09=RX1  PIO3_10=TXD
//   PIO3_11=MDIO PIO3_12=RXD  PIO3_13=TX_EN PIO3_14=TX1
//
// Port B (target/Pi Ethernet side):
//   PIO3_15=TX1  PIO3_16=TX_EN PIO3_17=RXD  PIO3_18=MDIO
//   PIO3_19=TXD  PIO3_20=RX1   PIO3_21=CRS  PIO3_22=MDC
//
// SPI to Pi (programmer header):
//   R11=SCK  R12=CS_N  P12=MISO
//
// Data flow:
//   rmii_rx_a → frame_tap_a → fwd_fifo_a → fwd_ctrl_a → rmii_tx_b
//   rmii_rx_b → frame_tap_b → fwd_fifo_b → fwd_ctrl_b → rmii_tx_a
//   frame_tap_a,b → cap_fifo → spi_slave → Pi
//
// Capture frame format in cap_fifo: [dir, len_h, len_l, data...]
//   dir=0x01: A→B (from router)   dir=0x02: B→A (from target)
`timescale 1ns/1ps

module top #(
    parameter CLK_HZ = 50_000_000
) (
    input  wire       clk,         // 50 MHz EXTCLK

    // ── Port A: router/switch side ────────────────────────────────────────
    input  wire [1:0] phy_a_rxd,   // RXD[1:0]  (RX1=bit1, RXD=bit0)
    input  wire       phy_a_crs,   // CRS_DV
    output wire [1:0] phy_a_txd,   // TXD[1:0]  (TX1=bit1, TXD=bit0)
    output wire       phy_a_tx_en,
    output wire       phy_a_mdc,
    inout  wire       phy_a_mdio,

    // ── Port B: target/Pi Ethernet side ──────────────────────────────────
    input  wire [1:0] phy_b_rxd,
    input  wire       phy_b_crs,
    output wire [1:0] phy_b_txd,
    output wire       phy_b_tx_en,
    output wire       phy_b_mdc,
    inout  wire       phy_b_mdio,

    // ── LED & button ──────────────────────────────────────────────────────
    output wire       led,
    input  wire       btn,

    // ── SPI to Pi ─────────────────────────────────────────────────────────
    input  wire       spi_sck,
    input  wire       spi_cs_n,
    output wire       spi_miso
);

    // ── Startup reset (16 cycles) ─────────────────────────────────────────
    reg [3:0] rst_cnt = 4'd0;
    reg       rst_n   = 1'b0;
    always @(posedge clk) begin
        if (!rst_n) begin
            if (rst_cnt == 4'd15) rst_n <= 1'b1;
            else                  rst_cnt <= rst_cnt + 4'd1;
        end
    end

    // ── MDC / MDIO: idle (no management traffic needed for tap) ──────────
    assign phy_a_mdc  = 1'b0;
    assign phy_b_mdc  = 1'b0;
    assign phy_a_mdio = 1'bz;   // hi-Z; pull-up on board
    assign phy_b_mdio = 1'bz;

    // ── RMII receivers ────────────────────────────────────────────────────
    wire       rx_a_valid, rx_a_sof, rx_a_eof;
    wire [7:0] rx_a_data;

    wire       rx_b_valid, rx_b_sof, rx_b_eof;
    wire [7:0] rx_b_data;

    rmii_rx rx_a_inst (
        .clk     (clk),
        .rst_n   (rst_n),
        .crs_dv  (phy_a_crs),
        .rxd     (phy_a_rxd),
        .rx_valid(rx_a_valid),
        .rx_data (rx_a_data),
        .rx_sof  (rx_a_sof),
        .rx_eof  (rx_a_eof)
    );

    rmii_rx rx_b_inst (
        .clk     (clk),
        .rst_n   (rst_n),
        .crs_dv  (phy_b_crs),
        .rxd     (phy_b_rxd),
        .rx_valid(rx_b_valid),
        .rx_data (rx_b_data),
        .rx_sof  (rx_b_sof),
        .rx_eof  (rx_b_eof)
    );

    // ── Forwarding FIFOs: 2 KB each ──────────────────────────────────────
    // fwd_a: frames from A, to be sent on B
    wire        fwd_a_wr_en,  fwd_a_rd_en;
    wire  [7:0] fwd_a_wr_data, fwd_a_rd_data;
    wire        fwd_a_full,   fwd_a_empty;

    bram_fifo #(.DATA_W(8), .DEPTH(2048), .ADDR_W(11)) fwd_a_fifo (
        .clk     (clk),
        .rst_n   (rst_n),
        .wr_en   (fwd_a_wr_en),
        .wr_data (fwd_a_wr_data),
        .wr_full (fwd_a_full),
        .rd_en   (fwd_a_rd_en),
        .rd_data (fwd_a_rd_data),
        .rd_empty(fwd_a_empty)
    );

    // fwd_b: frames from B, to be sent on A
    wire        fwd_b_wr_en,  fwd_b_rd_en;
    wire  [7:0] fwd_b_wr_data, fwd_b_rd_data;
    wire        fwd_b_full,   fwd_b_empty;

    bram_fifo #(.DATA_W(8), .DEPTH(2048), .ADDR_W(11)) fwd_b_fifo (
        .clk     (clk),
        .rst_n   (rst_n),
        .wr_en   (fwd_b_wr_en),
        .wr_data (fwd_b_wr_data),
        .wr_full (fwd_b_full),
        .rd_en   (fwd_b_rd_en),
        .rd_data (fwd_b_rd_data),
        .rd_empty(fwd_b_empty)
    );

    // ── Capture FIFO: 4 KB ───────────────────────────────────────────────
    wire        cap_wr_en_a,  cap_wr_en_b;
    wire  [7:0] cap_wr_data_a, cap_wr_data_b;
    wire        cap_full;
    wire        cap_rd_en;
    wire  [7:0] cap_rd_data;
    wire        cap_empty;

    // Arbitrate capture writes: A gets priority when both want to write.
    // In practice both ports can't flush simultaneously (both block on cap_full).
    wire        cap_wr_en   = cap_wr_en_a | cap_wr_en_b;
    wire  [7:0] cap_wr_data = cap_wr_en_a ? cap_wr_data_a : cap_wr_data_b;

    bram_fifo #(.DATA_W(8), .DEPTH(4096), .ADDR_W(12)) cap_fifo (
        .clk     (clk),
        .rst_n   (rst_n),
        .wr_en   (cap_wr_en),
        .wr_data (cap_wr_data),
        .wr_full (cap_full),
        .rd_en   (cap_rd_en),
        .rd_data (cap_rd_data),
        .rd_empty(cap_empty)
    );

    // ── Frame taps: buffer + dual-write ──────────────────────────────────
    frame_tap #(.DIR(8'h01)) tap_a (
        .clk        (clk),
        .rst_n      (rst_n),
        .rx_valid   (rx_a_valid),
        .rx_data    (rx_a_data),
        .rx_eof     (rx_a_eof),
        .fwd_wr_en  (fwd_a_wr_en),
        .fwd_wr_data(fwd_a_wr_data),
        .fwd_full   (fwd_a_full),
        .cap_wr_en  (cap_wr_en_a),
        .cap_wr_data(cap_wr_data_a),
        .cap_full   (cap_full)
    );

    frame_tap #(.DIR(8'h02)) tap_b (
        .clk        (clk),
        .rst_n      (rst_n),
        .rx_valid   (rx_b_valid),
        .rx_data    (rx_b_data),
        .rx_eof     (rx_b_eof),
        .fwd_wr_en  (fwd_b_wr_en),
        .fwd_wr_data(fwd_b_wr_data),
        .fwd_full   (fwd_b_full),
        .cap_wr_en  (cap_wr_en_b),
        .cap_wr_data(cap_wr_data_b),
        .cap_full   (cap_full)
    );

    // ── RMII transmitters ─────────────────────────────────────────────────
    wire [7:0] tx_a_data;
    wire       tx_a_valid, tx_a_eof, tx_a_ready;

    wire [7:0] tx_b_data;
    wire       tx_b_valid, tx_b_eof, tx_b_ready;

    rmii_tx tx_a_inst (
        .clk     (clk),
        .rst_n   (rst_n),
        .tx_data (tx_a_data),
        .tx_valid(tx_a_valid),
        .tx_eof  (tx_a_eof),
        .tx_ready(tx_a_ready),
        .txen    (phy_a_tx_en),
        .txd     (phy_a_txd)
    );

    rmii_tx tx_b_inst (
        .clk     (clk),
        .rst_n   (rst_n),
        .tx_data (tx_b_data),
        .tx_valid(tx_b_valid),
        .tx_eof  (tx_b_eof),
        .tx_ready(tx_b_ready),
        .txen    (phy_b_tx_en),
        .txd     (phy_b_txd)
    );

    // ── Forwarding controllers ────────────────────────────────────────────
    // fwd_b drives tx_a (B→A direction: target frames go to router)
    fwd_ctrl fwd_ctrl_b2a (
        .clk       (clk),
        .rst_n     (rst_n),
        .fifo_data (fwd_b_rd_data),
        .fifo_empty(fwd_b_empty),
        .fifo_rd   (fwd_b_rd_en),
        .tx_data   (tx_a_data),
        .tx_valid  (tx_a_valid),
        .tx_eof    (tx_a_eof),
        .tx_ready  (tx_a_ready)
    );

    // fwd_a drives tx_b (A→B direction: router frames go to target)
    fwd_ctrl fwd_ctrl_a2b (
        .clk       (clk),
        .rst_n     (rst_n),
        .fifo_data (fwd_a_rd_data),
        .fifo_empty(fwd_a_empty),
        .fifo_rd   (fwd_a_rd_en),
        .tx_data   (tx_b_data),
        .tx_valid  (tx_b_valid),
        .tx_eof    (tx_b_eof),
        .tx_ready  (tx_b_ready)
    );

    // ── SPI slave: stream cap_fifo to Pi ──────────────────────────────────
    spi_slave spi_inst (
        .clk       (clk),
        .rst_n     (rst_n),
        .fifo_data (cap_rd_data),
        .fifo_empty(cap_empty),
        .fifo_rd   (cap_rd_en),
        .spi_sck   (spi_sck),
        .spi_cs_n  (spi_cs_n),
        .spi_miso  (spi_miso)
    );

    // ── LED: diagnostic — latches when CRS_DV (Port B) falls after being HIGH
    // LED OFF after traffic: CRS_DV never de-asserts — check G2/PIO3_21 wiring.
    // LED ON  after traffic: CRS_DV toggles fine — bug is in rmii_rx or frame_tap.
    reg crs_was_high = 1'b0;
    reg crs_fell     = 1'b0;
    always @(posedge clk) begin
        if (phy_b_crs)                  crs_was_high <= 1'b1;
        if (crs_was_high && !phy_b_crs) crs_fell     <= 1'b1;
    end
    assign led = crs_fell;

endmodule
