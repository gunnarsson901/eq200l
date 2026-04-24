`timescale 1ns/1ps
module top (
    input  wire        clk_25m,          // 25 MHz onboard oscillator (P6)

    // ETH1 RMII — P2 connector (LAN8720 ETH1)
    input  wire        e1_ref_clk,       // 50 MHz ref clock from PHY  (L2)
    input  wire        e1_crs_dv,        // carrier sense / data valid  (M1)
    input  wire [1:0]  e1_rxd,           // receive data  [0]=M2, [1]=N1
    output wire        e1_txen,          // transmit enable             (N3)
    output wire [1:0]  e1_txd,           // transmit data [0]=P1, [1]=P2(ball)

    // ETH2 RMII — P3 connector (LAN8720 ETH2)
    input  wire        e2_ref_clk,       // 50 MHz ref clock from PHY  (A7)
    input  wire        e2_crs_dv,        // carrier sense / data valid  (B7)
    input  wire [1:0]  e2_rxd,           // receive data  [0]=A6, [1]=B6
    output wire        e2_txen,          // transmit enable             (A5)
    output wire [1:0]  e2_txd,           // transmit data [0]=B5, [1]=A4

    // Onboard RGB LED (active-low)
    output wire        led_r,            // A11
    output wire        led_g,            // A12
    output wire        led_b             // B11
);

    // ==================================================================
    // System clock: 25 MHz crystal directly (no PLL needed)
    // Bridge processes one byte/cycle; RMII delivers one byte per 4 PHY
    // cycles (~80 ns), so 25 MHz (40 ns) has 2x headroom.
    // ==================================================================
    wire clk_sys = clk_25m;

    // Simple power-on reset: hold rst_n low for 16 cycles after config
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
    //   p1 = ETH1,  p2 = ETH2
    //   p1_tx = data forwarded E2→E1
    //   p2_tx = data forwarded E1→E2
    // ==================================================================
    wire br_e1_rx_ready, br_e2_rx_ready;

    wire        br_p1_tx_valid, br_p1_tx_sof, br_p1_tx_eof;
    wire [7:0]  br_p1_tx_data;
    wire        br_p2_tx_valid, br_p2_tx_sof, br_p2_tx_eof;
    wire [7:0]  br_p2_tx_data;

    wire        e1_tx_fifo_full, e2_tx_fifo_full;

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
        .p1_tx_ready  (!e1_tx_fifo_full),

        .p2_tx_valid  (br_p2_tx_valid), .p2_tx_data(br_p2_tx_data),
        .p2_tx_sof    (br_p2_tx_sof),   .p2_tx_eof (br_p2_tx_eof),
        .p2_tx_ready  (!e2_tx_fifo_full),

        // P3 monitor: not wired in this design (TODO: UART capture)
        .p3_tx_valid  (),
        .p3_tx_data   (),
        .p3_tx_sof    (),
        .p3_tx_eof    (),
        .p3_tx_ready  (1'b1),

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
    // Carries E2→E1 forwarded frames (bridge p1_tx output)
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
    // Carries E1→E2 forwarded frames (bridge p2_tx output)
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
        .rd_clk  (e2_ref_clk),  .rd_rst_n(rst_n),
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
    // LEDs (active-low)
    //   R: off once PLL locks
    //   G: pulses on ETH1 RX activity
    //   B: pulses on ETH2 RX activity
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

    assign led_r = ~rst_n;          // lights during reset, off once running
    assign led_g = ~|e1_stretch;    // ETH1 activity
    assign led_b = ~|e2_stretch;    // ETH2 activity

endmodule
