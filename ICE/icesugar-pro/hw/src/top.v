`timescale 1ns/1ps
module top (
    input  wire        clk_25m,          // 25 MHz onboard oscillator (P6)

    // ETH1 RMII — P2 connector (LAN8720 ETH1, Pi 4)
    input  wire        e1_ref_clk,       // 50 MHz ref clock from PHY  (L2)
    input  wire        e1_crs_dv,        // carrier sense / data valid  (M1)
    input  wire [1:0]  e1_rxd,           // receive data  [0]=M2, [1]=N1
    output wire        e1_txen,          // transmit enable             (N3)
    output wire [1:0]  e1_txd,           // transmit data [0]=P1, [1]=P2(ball)

    // ETH1 MDIO/MDC — P2 connector
    output wire        e1_mdc,
    inout  wire        e1_mdio,

    // ETH2 RMII — P3 connector on BRB → LAN8720 ETH2
    input  wire        e2_ref_clk,       // 50 MHz REFCLKO from LAN8720 XTS crystal (B7)
    input  wire        e2_crs_dv,        // carrier sense / data valid  (A7)
    input  wire [1:0]  e2_rxd,           // receive data  [0]=A6, [1]=B6
    output wire        e2_txen,          // transmit enable             (A5)
    output wire [1:0]  e2_txd,           // transmit data [0]=B5, [1]=A4

    // ETH2 MDIO/MDC — P3 connector
    output wire        e2_mdc,
    inout  wire        e2_mdio,

    // UART capture — P5 GPIO header
    // uart_tx (B3, SODIMM 73) → Pi GPIO 15 (physical pin 10, /dev/serial0 RX)
    // uart_rx (A3, SODIMM 71) ← Pi GPIO 14 (physical pin 8,  /dev/serial0 TX) [optional]
    output wire        uart_tx,          // B3 SODIMM-73 — captured frames to Pi
    input  wire        uart_rx,          // A3 SODIMM-71 — commands from Pi (future)

    // SPI — Pi master, FPGA slave
    // Pi SPI0: MOSI=GPIO10, MISO=GPIO9, SCLK=GPIO11, CS=GPIO24
    input  wire        spi_sclk,         // D1
    input  wire        spi_mosi,         // E1 (ignored for now — receive-only slave)
    output wire        spi_miso,         // F2
    input  wire        spi_cs_n,         // C2

    // Onboard RGB LED (active-low)
    output wire        led_r,            // A11
    output wire        led_g,            // A12
    output wire        led_b             // B11
);

    // ==================================================================
    // System clock: 25 MHz crystal directly
    // ==================================================================
    wire clk_sys = clk_25m;

    // Power-on reset: hold rst_n low for 16 cycles after FPGA config
    reg [3:0] rst_ctr = 4'd0;
    wire rst_n = rst_ctr[3];
    always @(posedge clk_sys)
        if (!rst_n) rst_ctr <= rst_ctr + 1;

    // ==================================================================
    // ETH1 RX  (e1_ref_clk → clk_sys via async FIFO)
    // ==================================================================
    wire        e1_rx_valid, e1_rx_sof, e1_rx_eof;
    wire [7:0]  e1_rx_data;

    rmii_rx e1_rx_inst (
        .clk     (e1_ref_clk),
        .rst_n   (rst_n),
        .crs_dv  (e1_crs_dv),
        .rxd     (e1_rxd),
        .rx_valid(e1_rx_valid),
        .rx_data (e1_rx_data),
        .rx_sof  (e1_rx_sof),
        .rx_eof  (e1_rx_eof)
    );

    wire [9:0]  e1_rx_fifo_wdata = {e1_rx_sof, e1_rx_eof, e1_rx_data};
    wire        e1_rx_fifo_full,  e1_rx_fifo_empty;
    wire [9:0]  e1_rx_fifo_rdata;
    wire        e1_rx_fifo_rd_en;

    async_fifo #(.DATA_W(10), .DEPTH(64), .ADDR_W(6)) fifo_e1_rx (
        .wr_clk  (e1_ref_clk), .wr_rst_n(rst_n),
        .wr_en   (e1_rx_valid && !e1_rx_fifo_full),
        .wr_data (e1_rx_fifo_wdata),
        .wr_full (e1_rx_fifo_full),
        .rd_clk  (clk_sys),    .rd_rst_n(rst_n),
        .rd_en   (e1_rx_fifo_rd_en),
        .rd_data (e1_rx_fifo_rdata),
        .rd_empty(e1_rx_fifo_empty)
    );

    wire br_e1_rx_valid = !e1_rx_fifo_empty;
    wire br_e1_rx_sof   = e1_rx_fifo_rdata[9];
    wire br_e1_rx_eof   = e1_rx_fifo_rdata[8];
    wire [7:0] br_e1_rx_data = e1_rx_fifo_rdata[7:0];

    // ==================================================================
    // ETH2 RX  (e2_ref_clk → clk_sys via async FIFO)
    // ==================================================================
    wire        e2_rx_valid, e2_rx_sof, e2_rx_eof;
    wire [7:0]  e2_rx_data;

    rmii_rx e2_rx_inst (
        .clk     (e2_ref_clk),
        .rst_n   (rst_n),
        .crs_dv  (e2_crs_dv),
        .rxd     (e2_rxd),
        .rx_valid(e2_rx_valid),
        .rx_data (e2_rx_data),
        .rx_sof  (e2_rx_sof),
        .rx_eof  (e2_rx_eof)
    );

    wire [9:0]  e2_rx_fifo_wdata = {e2_rx_sof, e2_rx_eof, e2_rx_data};
    wire        e2_rx_fifo_full,  e2_rx_fifo_empty;
    wire [9:0]  e2_rx_fifo_rdata;
    wire        e2_rx_fifo_rd_en;

    async_fifo #(.DATA_W(10), .DEPTH(64), .ADDR_W(6)) fifo_e2_rx (
        .wr_clk  (e2_ref_clk), .wr_rst_n(rst_n),
        .wr_en   (e2_rx_valid && !e2_rx_fifo_full),
        .wr_data (e2_rx_fifo_wdata),
        .wr_full (e2_rx_fifo_full),
        .rd_clk  (clk_sys),    .rd_rst_n(rst_n),
        .rd_en   (e2_rx_fifo_rd_en),
        .rd_data (e2_rx_fifo_rdata),
        .rd_empty(e2_rx_fifo_empty)
    );

    wire br_e2_rx_valid = !e2_rx_fifo_empty;
    wire br_e2_rx_sof   = e2_rx_fifo_rdata[9];
    wire br_e2_rx_eof   = e2_rx_fifo_rdata[8];
    wire [7:0] br_e2_rx_data = e2_rx_fifo_rdata[7:0];

    // ==================================================================
    // PHY Bridge  (clk_sys domain)
    //   p1 = ETH1 (Pi),  p2 = ETH2 (Router)
    //   p1_tx = E2→E1 forwarded,  p2_tx = E1→E2 forwarded
    //   p3 = mirror of both directions → UART capture
    // ==================================================================
    wire br_e1_rx_ready, br_e2_rx_ready;

    wire        br_p1_tx_valid, br_p1_tx_sof, br_p1_tx_eof;
    wire [7:0]  br_p1_tx_data;
    wire        br_p2_tx_valid, br_p2_tx_sof, br_p2_tx_eof;
    wire [7:0]  br_p2_tx_data;
    wire        br_p3_tx_valid, br_p3_tx_sof, br_p3_tx_eof, br_p3_tx_dir;
    wire [7:0]  br_p3_tx_data;

    wire        e1_tx_fifo_full, e2_tx_fifo_full;
    wire        cap_fifo_full;

    assign e1_rx_fifo_rd_en = br_e1_rx_ready;
    assign e2_rx_fifo_rd_en = br_e2_rx_ready;

    wire [31:0] pkt_cnt_e1, pkt_cnt_e2;

    phy_bridge bridge (
        .clk_sys      (clk_sys),
        .rst_n        (rst_n),

        .p1_rx_valid  (br_e1_rx_valid), .p1_rx_data(br_e1_rx_data),
        .p1_rx_sof    (br_e1_rx_sof),   .p1_rx_eof (br_e1_rx_eof),
        .p1_rx_ready  (br_e1_rx_ready),

        .p2_rx_valid  (br_e2_rx_valid), .p2_rx_data(br_e2_rx_data),
        .p2_rx_sof    (br_e2_rx_sof),   .p2_rx_eof (br_e2_rx_eof),
        .p2_rx_ready  (br_e2_rx_ready),

        .p1_tx_valid  (br_p1_tx_valid), .p1_tx_data(br_p1_tx_data),
        .p1_tx_sof    (br_p1_tx_sof),   .p1_tx_eof (br_p1_tx_eof),
        .p1_tx_ready  (1'b1),            // ETH1 not connected — always drain ETH2

        .p2_tx_valid  (br_p2_tx_valid), .p2_tx_data(br_p2_tx_data),
        .p2_tx_sof    (br_p2_tx_sof),   .p2_tx_eof (br_p2_tx_eof),
        .p2_tx_ready  (1'b1),            // ETH2 not connected — always drain ETH1

        .p3_tx_valid  (br_p3_tx_valid), .p3_tx_data(br_p3_tx_data),
        .p3_tx_sof    (br_p3_tx_sof),   .p3_tx_eof (br_p3_tx_eof),
        .p3_tx_dir    (br_p3_tx_dir),
        .p3_tx_ready  (!cap_fifo_full),

        .mitm_en      (1'b0),
        .mitm_byte_idx(8'd0),
        .mitm_match   (8'd0),
        .mitm_replace (8'd0),
        .sw_rst       (1'b0),

        .pkt_count_p1 (pkt_cnt_e1),
        .pkt_count_p2 (pkt_cnt_e2)
    );

    // ==================================================================
    // ETH1 TX  (clk_sys → e1_ref_clk via async FIFO → rmii_tx)
    // ==================================================================
    wire [8:0]  e1_tx_fifo_wdata = {br_p1_tx_eof, br_p1_tx_data};
    wire        e1_tx_fifo_empty;
    wire [8:0]  e1_tx_fifo_rdata;
    wire        e1_tx_fifo_rd_en;

    async_fifo #(.DATA_W(9), .DEPTH(64), .ADDR_W(6)) fifo_e1_tx (
        .wr_clk  (clk_sys),     .wr_rst_n(rst_n),
        .wr_en   (br_p1_tx_valid && !e1_tx_fifo_full),
        .wr_data (e1_tx_fifo_wdata),
        .wr_full (e1_tx_fifo_full),
        .rd_clk  (e1_ref_clk),  .rd_rst_n(rst_n),
        .rd_en   (e1_tx_fifo_rd_en),
        .rd_data (e1_tx_fifo_rdata),
        .rd_empty(e1_tx_fifo_empty)
    );

    wire e1_tx_ready;
    rmii_tx e1_tx_inst (
        .clk     (e1_ref_clk),
        .rst_n   (rst_n),
        .tx_data (e1_tx_fifo_rdata[7:0]),
        .tx_valid(!e1_tx_fifo_empty),
        .tx_eof  (e1_tx_fifo_rdata[8]),
        .tx_ready(e1_tx_ready),
        .txen    (e1_txen),
        .txd     (e1_txd)
    );
    assign e1_tx_fifo_rd_en = e1_tx_ready;

    // ==================================================================
    // ETH2 TX  (clk_sys → e2_ref_clk via async FIFO → rmii_tx)
    // ==================================================================
    wire [8:0]  e2_tx_fifo_wdata = {br_p2_tx_eof, br_p2_tx_data};
    wire        e2_tx_fifo_empty;
    wire [8:0]  e2_tx_fifo_rdata;
    wire        e2_tx_fifo_rd_en;

    async_fifo #(.DATA_W(9), .DEPTH(64), .ADDR_W(6)) fifo_e2_tx (
        .wr_clk  (clk_sys),     .wr_rst_n(rst_n),
        .wr_en   (br_p2_tx_valid && !e2_tx_fifo_full),
        .wr_data (e2_tx_fifo_wdata),
        .wr_full (e2_tx_fifo_full),
        .rd_clk  (e2_ref_clk),     .rd_rst_n(rst_n),
        .rd_en   (e2_tx_fifo_rd_en),
        .rd_data (e2_tx_fifo_rdata),
        .rd_empty(e2_tx_fifo_empty)
    );

    wire e2_tx_ready;
    rmii_tx e2_tx_inst (
        .clk     (e2_ref_clk),
        .rst_n   (rst_n),
        .tx_data (e2_tx_fifo_rdata[7:0]),
        .tx_valid(!e2_tx_fifo_empty),
        .tx_eof  (e2_tx_fifo_rdata[8]),
        .tx_ready(e2_tx_ready),
        .txen    (e2_txen),
        .txd     (e2_txd)
    );
    assign e2_tx_fifo_rd_en = e2_tx_ready;

    // ==================================================================
    // UART Capture Path
    //   P3 mirror → capture FIFO → frame_uart → uart_tx pin
    //   Frame format: 0xAA 0x55 | data (0xAA→0xAA 0x00) | 0xAA 0x56
    //   Baud: 1 Mbit/s  — on Pi: stty -F /dev/serial0 1000000 raw
    // ==================================================================
    // 11-bit entries: {dir, sof, eof, data[7:0]}
    // depth 2048 holds >1 full max-size Ethernet frame (1518 bytes) per direction
    wire [10:0] cap_fifo_wdata = {br_p3_tx_dir, br_p3_tx_sof, br_p3_tx_eof, br_p3_tx_data};
    wire        cap_fifo_empty;
    wire [10:0] cap_fifo_rdata;
    wire        cap_fifo_rd_en;

    bram_fifo #(.DATA_W(11), .DEPTH(2048), .ADDR_W(11)) cap_fifo (
        .clk     (clk_sys),
        .rst_n   (rst_n),
        .wr_en   (br_p3_tx_valid && !cap_fifo_full),
        .wr_data (cap_fifo_wdata),
        .wr_full (cap_fifo_full),
        .rd_en   (cap_fifo_rd_en),
        .rd_data (cap_fifo_rdata),
        .rd_empty(cap_fifo_empty)
    );

    // Beacon: send 0xDE 0xAD 0xBE 0xEF every ~1s when cap_fifo is empty,
    // so we can verify the uart_tx wire works regardless of Ethernet traffic.
    reg [24:0] bcn_cnt;
    reg [2:0]  bcn_state;
    reg        bcn_valid, bcn_sof, bcn_eof;
    reg [7:0]  bcn_data;
    localparam BCN_IDLE=3'd0, BCN_B0=3'd1, BCN_B1=3'd2,
               BCN_B2=3'd3,   BCN_B3=3'd4;

    wire        fu_in_ready;
    wire        use_bcn = bcn_valid && cap_fifo_empty;
    wire        fu_in_valid = 1'b0;   // UART disabled — SPI handles capture
    wire        fu_in_sof   = use_bcn ? bcn_sof       : cap_fifo_rdata[9];
    wire        fu_in_eof   = use_bcn ? bcn_eof       : cap_fifo_rdata[8];
    wire [7:0]  fu_in_data  = use_bcn ? bcn_data      : cap_fifo_rdata[7:0];
    wire        fu_in_dir   = use_bcn ? 1'b0          : cap_fifo_rdata[10];
    assign      cap_fifo_rd_en = (spi_state == SP_DATA) && spi_fifo_rd && !cap_fifo_empty;

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            bcn_cnt   <= 0;
            bcn_state <= BCN_IDLE;
            bcn_valid <= 1'b0;
            bcn_sof   <= 1'b0;
            bcn_eof   <= 1'b0;
            bcn_data  <= 8'h00;
        end else begin
            case (bcn_state)
                BCN_IDLE: begin
                    bcn_valid <= 1'b0;
                    if (bcn_cnt == 25'd24_999_999) begin
                        bcn_cnt   <= 0;
                        bcn_state <= BCN_B0;
                        bcn_valid <= 1'b1;
                        bcn_sof   <= 1'b1;
                        bcn_eof   <= 1'b0;
                        bcn_data  <= 8'h42;   // 'B'
                    end else
                        bcn_cnt <= bcn_cnt + 1;
                end
                BCN_B0: if (use_bcn && fu_in_ready) begin
                    bcn_sof   <= 1'b0;
                    bcn_data  <= 8'h45;   // 'E'
                    bcn_state <= BCN_B1;
                end
                BCN_B1: if (use_bcn && fu_in_ready) begin
                    bcn_data  <= 8'h45;   // 'E'
                    bcn_state <= BCN_B2;
                end
                BCN_B2: if (use_bcn && fu_in_ready) begin
                    bcn_data  <= 8'h46;   // 'F'
                    bcn_eof   <= 1'b1;
                    bcn_state <= BCN_B3;
                end
                BCN_B3: if (use_bcn && fu_in_ready) begin
                    bcn_valid <= 1'b0;
                    bcn_eof   <= 1'b0;
                    bcn_state <= BCN_IDLE;
                end
                default: bcn_state <= BCN_IDLE;
            endcase
        end
    end

    frame_uart #(.CLK_HZ(25_000_000), .BAUD(1_000_000)) fu (
        .clk      (clk_sys),
        .rst_n    (rst_n),
        .in_valid (fu_in_valid),
        .in_data  (fu_in_data),
        .in_sof   (fu_in_sof),
        .in_eof   (fu_in_eof),
        .in_dir   (fu_in_dir),
        .in_ready (fu_in_ready),
        .tx       (uart_tx),
        .rx       (uart_rx)
    );

    // ==================================================================
    // MDIO — PHY management
    //   Polls Basic Status Register (reg 1, bit 2 = link up) every ~1 s.
    //   CLK_DIV=12 → MDC = 25 MHz / 24 ≈ 1 MHz
    // ==================================================================
    wire e1_mdio_oe, e1_mdio_out, e1_mdio_in;
    wire e2_mdio_oe, e2_mdio_out, e2_mdio_in;

    assign e1_mdio    = e1_mdio_oe ? e1_mdio_out : 1'bz;
    assign e1_mdio_in = e1_mdio;
    assign e2_mdio    = e2_mdio_oe ? e2_mdio_out : 1'bz;
    assign e2_mdio_in = e2_mdio;

    wire        m1_busy, m1_done, m1_rdata_valid;
    reg         m1_req;
    wire [15:0] m1_rdata;
    reg  [4:0]  m1_reg_addr;

    mdio_master #(.CLK_DIV(12), .PHY_ADDR(5'd0)) mdio1 (
        .clk(clk_sys), .rst_n(rst_n),
        .mdc(e1_mdc), .mdio_oe(e1_mdio_oe),
        .mdio_out(e1_mdio_out), .mdio_in(e1_mdio_in),
        .req(m1_req), .wr(1'b0), .reg_addr(m1_reg_addr), .wdata(16'h0),
        .busy(m1_busy), .done(m1_done), .rdata(m1_rdata), .rdata_valid(m1_rdata_valid)
    );

    wire        m2_busy, m2_done, m2_rdata_valid;
    reg         m2_req;
    wire [15:0] m2_rdata;
    reg  [4:0]  m2_reg_addr;

    mdio_master #(.CLK_DIV(12), .PHY_ADDR(5'd0)) mdio2 (
        .clk(clk_sys), .rst_n(rst_n),
        .mdc(e2_mdc), .mdio_oe(e2_mdio_oe),
        .mdio_out(e2_mdio_out), .mdio_in(e2_mdio_in),
        .req(m2_req), .wr(1'b0), .reg_addr(m2_reg_addr), .wdata(16'h0),
        .busy(m2_busy), .done(m2_done), .rdata(m2_rdata), .rdata_valid(m2_rdata_valid)
    );

    // Poll sequencer
    reg [1:0]  link_up;      // [0]=PHY1 (ETH1/Pi), [1]=PHY2 (ETH2/Router)
    reg [24:0] poll_timer;
    reg [2:0]  poll_state;

    localparam PL_PWRUP = 3'd0;   // 100 ms PHY powerup hold
    localparam PL_RD1   = 3'd1;
    localparam PL_WAIT1 = 3'd2;
    localparam PL_RD2   = 3'd3;
    localparam PL_WAIT2 = 3'd4;
    localparam PL_IDLE  = 3'd5;   // 1 s between polls

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            poll_state  <= PL_PWRUP;
            poll_timer  <= 0;
            link_up     <= 2'b00;
            m1_req      <= 0;  m1_reg_addr <= 5'd1;
            m2_req      <= 0;  m2_reg_addr <= 5'd1;
        end else begin
            m1_req <= 0;
            m2_req <= 0;
            case (poll_state)
                PL_PWRUP: begin
                    if (poll_timer == 25'd2_499_999) begin  // 100 ms
                        poll_timer <= 0;
                        poll_state <= PL_RD1;
                    end else
                        poll_timer <= poll_timer + 1;
                end
                PL_RD1: begin
                    m1_req     <= 1;
                    poll_state <= PL_WAIT1;
                end
                PL_WAIT1: begin
                    if (m1_rdata_valid) begin
                        // 0xFFFF = floating mdio_in (no PHY); treat as link-down
                        link_up[0] <= (m1_rdata != 16'hFFFF) && m1_rdata[2];
                        poll_state <= PL_RD2;
                    end
                end
                PL_RD2: begin
                    m2_req     <= 1;
                    poll_state <= PL_WAIT2;
                end
                PL_WAIT2: begin
                    if (m2_rdata_valid) begin
                        link_up[1] <= (m2_rdata != 16'hFFFF) && m2_rdata[2];
                        poll_state <= PL_IDLE;
                    end
                end
                PL_IDLE: begin
                    if (poll_timer == 25'd24_999_999) begin  // 1 s
                        poll_timer <= 0;
                        poll_state <= PL_RD1;
                    end else
                        poll_timer <= poll_timer + 1;
                end
                default: poll_state <= PL_PWRUP;
            endcase
        end
    end

    // ==================================================================
    // LEDs (active-low)
    //   R: on during reset
    //   G: ETH1 RX activity (Pi side)
    //   B: ETH2 RX activity (Router side)
    // ==================================================================
    reg [19:0] e1_stretch, e2_stretch;

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            e1_stretch <= 0;
            e2_stretch <= 0;
        end else begin
            if (br_e1_rx_valid)    e1_stretch <= 20'hFFFFF;
            else if (|e1_stretch)  e1_stretch <= e1_stretch - 1;

            if (br_e2_rx_valid)    e2_stretch <= 20'hFFFFF;
            else if (|e2_stretch)  e2_stretch <= e2_stretch - 1;
        end
    end

    assign led_r = ~rst_n;
    assign led_g = link_up[1] ? ~|e2_stretch : 1'b1;  // blinks on ETH2 RX
    assign led_b = ~link_up[1];                        // on = ETH2 link down

    // ==================================================================
    // SPI Capture Path
    //   Streams cap_fifo to Pi with 0xFE SOF markers between frames.
    //   Idle output: 0xFF (spi_slave default when fifo_empty).
    //   Frame wire format: 0xFE <data bytes...>  (next frame: 0xFE ...)
    // ==================================================================
    localparam SP_IDLE = 2'd0;
    localparam SP_SOF  = 2'd1;
    localparam SP_DATA = 2'd2;

    reg  [1:0] spi_state;
    wire       spi_fifo_rd;

    wire [7:0] spi_byte_out = (spi_state == SP_SOF) ? 8'hFE : cap_fifo_rdata[7:0];
    wire       spi_byte_vld = (spi_state == SP_SOF) ||
                              (spi_state == SP_DATA && !cap_fifo_empty);

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            spi_state <= SP_IDLE;
        end else begin
            case (spi_state)
                SP_IDLE: begin
                    // Wait for a frame SOF to appear at the cap_fifo head
                    if (!cap_fifo_empty && cap_fifo_rdata[9])
                        spi_state <= SP_SOF;
                end
                SP_SOF: begin
                    // Sending 0xFE marker; advance when spi_slave consumes it
                    if (spi_fifo_rd)
                        spi_state <= SP_DATA;
                end
                SP_DATA: begin
                    if (spi_fifo_rd && !cap_fifo_empty && cap_fifo_rdata[8])  // EOF consumed
                        spi_state <= SP_IDLE;
                end
                default: spi_state <= SP_IDLE;
            endcase
        end
    end

    spi_slave spi_s (
        .clk       (clk_sys),
        .rst_n     (rst_n),
        .fifo_data (spi_byte_out),
        .fifo_empty(!spi_byte_vld),
        .fifo_rd   (spi_fifo_rd),
        .spi_sck   (spi_sclk),
        .spi_cs_n  (spi_cs_n),
        .spi_miso  (spi_miso)
    );

endmodule
