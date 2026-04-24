// iCE40HX8K – LAN8720 RMII network tap
//
// Clock domain: 50 MHz from LAN8720 NINT/REFCLK → J3 (GBIN6).
//
// Data path:
//   LAN8720 RMII → rmii_rx → frame_store → sync_fifo (4 KB) → spi_slave → Pi SPI
//
// frame_store buffers one complete Ethernet frame (≤1518 B), then flushes
//   [len_h, len_l, byte_0 … byte_N-1] into the FIFO.
// spi_slave streams FIFO bytes to Pi MSB-first; returns 0xFF when FIFO is empty.
// Pi spi_read.py hunts for len_h (0x00–0x05), reads len_l + N frame bytes.
//
// Pin mapping — see top.pcf.
`timescale 1ns/1ps

module top (
    // ----------------------------------------------------------------
    // LAN8720 RMII — inputs
    // ----------------------------------------------------------------
    input  wire       ref_clk,    // 50 MHz NINT/REFCLK  (J3 / GBIN6)
    input  wire       crs_dv,     // Carrier Sense / Data Valid  (G2 / pi03_21)
    input  wire       rxd0,       // RXD dibit bit 0             (F2 / pi03_17)
    input  wire       rxd1,       // RX1 dibit bit 1             (H4 / pi03_20)

    // ----------------------------------------------------------------
    // LAN8720 RMII — outputs (TX unused, held idle)
    // ----------------------------------------------------------------
    output wire       txen,       // TX Enable  (H3 / pi03_16)
    output wire       txd0,       // TXD bit 0  (F1 / pi03_19)
    output wire       txd1,       // TX1 bit 1  (F3 / pi03_15)

    // ----------------------------------------------------------------
    // LAN8720 management bus
    // ----------------------------------------------------------------
    output wire       mdc,        // MDC   (J4 / pi03_22)
    output wire       mdio_out,   // MDIO  (H6 / pi03_18)

    // ----------------------------------------------------------------
    // SPI slave → Raspberry Pi (PGM1 header, runtime reuse)
    // ----------------------------------------------------------------
    input  wire       spi_sck,    // R11 — Pi GPIO11 SPI0_CLK
    input  wire       spi_cs_n,   // R12 — Pi GPIO8  SPI0_CE0_N
    output wire       spi_miso,   // P12 — Pi GPIO9  SPI0_MISO

    // ----------------------------------------------------------------
    // Board LEDs
    // ----------------------------------------------------------------
    output wire       led1,       // M12 — toggles each received frame
    output wire       led2,       // R16 — lit while FIFO non-empty

    // ----------------------------------------------------------------
    // Clock-alive diagnostics (J2 pins probed by Logic2)
    // ----------------------------------------------------------------
    output wire       dbg0,       // D2  — ref_clk/2^26 ≈ 0.74 Hz
    output wire       dbg1,       // G5  — ref_clk/2^25 ≈ 1.5  Hz
    output wire       dbg2,       // D1  — ref_clk/2^24 ≈ 3    Hz
    output wire       dbg3        // G4  — rx_valid pulse (per received byte)
);

    // ------------------------------------------------------------------
    // PHY reset sequencer
    // Hold phy_rst_n low for 5 000 cycles (100 µs at 50 MHz), then
    // release.  LAN8720 needs ≥100 µs reset pulse.  Auto-neg adds ~1 s
    // before link is up, handled by the PHY autonomously.
    // ------------------------------------------------------------------
    reg [12:0] rst_cnt  = 0;
    reg        phy_rst_r = 0;

    always @(posedge ref_clk) begin
        if (!phy_rst_r) begin
            if (rst_cnt == 13'd4999)
                phy_rst_r <= 1'b1;
            else
                rst_cnt <= rst_cnt + 1'b1;
        end
    end

    // phy_rst_n not exported — LAN8720 uses internal POR.
    // phy_rst_r is used as the internal reset release flag.
    wire rst_n = phy_rst_r;

    // ------------------------------------------------------------------
    // RMII RX
    // ------------------------------------------------------------------
    wire       rx_valid;
    wire [7:0] rx_data;
    wire       rx_sof;   // first byte of frame (unused here)
    wire       rx_eof;   // last byte of frame  (unused here)

    rmii_rx rx_inst (
        .clk     (ref_clk),
        .rst_n   (rst_n),
        .crs_dv  (crs_dv),
        .rxd     ({rxd1, rxd0}),
        .rx_valid(rx_valid),
        .rx_data (rx_data),
        .rx_sof  (rx_sof),
        .rx_eof  (rx_eof)
    );

    // ------------------------------------------------------------------
    // Frame store — buffers one full Ethernet frame (up to 1518 B) then
    // flushes [len_h, len_l, data…] into the FIFO.  Frames arriving
    // during a flush are silently dropped (passive-tap is acceptable).
    // ------------------------------------------------------------------
    wire       fifo_full;
    wire       fifo_empty;
    wire [7:0] fifo_rdata;
    wire       fifo_rd_en;

    wire       fs_wr_en;
    wire [7:0] fs_wr_data;

    frame_store fs_inst (
        .clk         (ref_clk),
        .rst_n       (rst_n),
        .rx_valid    (rx_valid),
        .rx_data     (rx_data),
        .rx_eof      (rx_eof),
        .fifo_wr_en  (fs_wr_en),
        .fifo_wr_data(fs_wr_data),
        .fifo_full   (fifo_full)
    );

    // ------------------------------------------------------------------
    // 256-byte synchronous FIFO (async read → LUT-based, not EBR).
    // frame_store stalls on full and drains gradually via SPI.
    // Large frames are captured correctly; they just take longer to flush.
    // ------------------------------------------------------------------
    sync_fifo #(
        .DATA_W (8),
        .DEPTH  (256),
        .ADDR_W (8)
    ) fifo_inst (
        .clk     (ref_clk),
        .rst_n   (rst_n),
        .wr_en   (fs_wr_en),
        .wr_data (fs_wr_data),
        .wr_full (fifo_full),
        .rd_en   (fifo_rd_en),
        .rd_data (fifo_rdata),
        .rd_empty(fifo_empty)
    );

    // ------------------------------------------------------------------
    // SPI slave — drain FIFO on demand from Pi
    // ------------------------------------------------------------------
    spi_slave spi_inst (
        .clk        (ref_clk),
        .rst_n      (rst_n),
        .fifo_data  (fifo_rdata),
        .fifo_empty (fifo_empty),
        .fifo_rd    (fifo_rd_en),
        .spi_sck    (spi_sck),
        .spi_cs_n   (spi_cs_n),
        .spi_miso   (spi_miso)
    );

    // ------------------------------------------------------------------
    // TX side — idle (receive-only tap)
    // ------------------------------------------------------------------
    assign txen     = 1'b0;
    assign txd0     = 1'b0;
    assign txd1     = 1'b0;

    // MDIO management bus — idle state
    assign mdc      = 1'b0;
    assign mdio_out = 1'b1;   // MDIO idles high

    // ------------------------------------------------------------------
    // LED indicators
    //   led1 — toggles on every rx_eof (one Ethernet frame received)
    //   led2 — lit whenever the FIFO holds data (PHY is feeding bytes)
    // ------------------------------------------------------------------
    reg led1_r = 1'b0;
    always @(posedge ref_clk)
        if (rx_eof) led1_r <= ~led1_r;

    assign led1 = led1_r;
    assign led2 = ~fifo_empty;

    // ------------------------------------------------------------------
    // Clock-alive diagnostics — free-running counter on ref_clk.
    // If E4 has the 50 MHz REFCLK these will toggle at visible rates.
    // ------------------------------------------------------------------
    reg [25:0] clk_cnt = 26'd0;
    always @(posedge ref_clk) clk_cnt <= clk_cnt + 1'b1;

    assign dbg0 = clk_cnt[25];   // 50 MHz / 2^26 ≈ 0.74 Hz
    assign dbg1 = clk_cnt[24];   // 50 MHz / 2^25 ≈ 1.49 Hz
    assign dbg2 = clk_cnt[23];   // 50 MHz / 2^24 ≈ 2.98 Hz
    assign dbg3 = rx_valid;      // pulse on every received RMII byte

endmodule
