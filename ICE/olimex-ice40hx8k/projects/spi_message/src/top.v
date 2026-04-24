// spi_message — send "BTN\n" over SPI each time the button is pressed.
//
// The Pi polls with single-byte SPI reads (sending 0xFF as dummy).
// While idle the FPGA returns 0xFF.  After a button press it queues
// "BTN\n" (4 bytes) and the next 4 polls receive B T N \n in order.
//
// Pins (ICE40HX8K-CT256):
//   clk      J3   GBIN6  50 MHz LAN8720 NINT/REFCLK
//   btn      F4   active-low button
//   led      C2   active-high LED (lit while button held)
//   spi_sck  R11  Pi GPIO11  SPI0_CLK
//   spi_cs_n R12  Pi GPIO8   SPI0_CE0_N
//   spi_miso P12  Pi GPIO9   SPI0_MISO
`timescale 1ns/1ps

module top #(
    parameter CLK_HZ = 50_000_000
) (
    input  wire clk,
    input  wire btn,
    output wire led,
    input  wire spi_sck,
    input  wire spi_cs_n,
    output wire spi_miso
);

    // ── Startup reset ─────────────────────────────────────────────────────
    // Hold rst_n low for 16 cycles so spi_slave initialises shreg = 0xFF.
    // iCE40 registers default to 0 after configuration, so rst_cnt/rst_n
    // reliably start at 0 without needing initial-value declarations.
    reg [3:0] rst_cnt = 4'd0;
    reg       rst_n   = 1'b0;
    always @(posedge clk) begin
        if (!rst_n) begin
            if (rst_cnt == 4'd15) rst_n <= 1'b1;
            else                  rst_cnt <= rst_cnt + 4'd1;
        end
    end

    // ── Button debounce ───────────────────────────────────────────────────
    localparam [19:0] DBNC = CLK_HZ / 100;   // 10 ms

    reg [19:0] dbnc_cnt = 0;
    reg        btn_sync;
    reg        btn_db   = 1'b1;
    reg        btn_db_r = 1'b1;

    always @(posedge clk) btn_sync <= btn;

    always @(posedge clk) begin
        btn_db_r <= btn_db;
        if (btn_sync == btn_db) begin
            dbnc_cnt <= 0;
        end else if (dbnc_cnt == DBNC - 1) begin
            btn_db   <= btn_sync;
            dbnc_cnt <= 0;
        end else begin
            dbnc_cnt <= dbnc_cnt + 1;
        end
    end

    wire btn_press = btn_db_r & ~btn_db;   // one-cycle pulse on press

    // LED on while button held — simpler and more reliable than edge-based blink
    assign led = ~btn_db;

    // ── 4-byte FIFO: "BTN\n" queued on button press ───────────────────────────
    // Simple shift-register FIFO: msg[3:0] holds up to 4 bytes; cnt tracks fill.
    // On btn_press: load all 4 bytes. On fifo_rd: shift out the head byte.
    localparam [7:0] MSG0 = 8'h42; // 'B'
    localparam [7:0] MSG1 = 8'h54; // 'T'
    localparam [7:0] MSG2 = 8'h4E; // 'N'
    localparam [7:0] MSG3 = 8'h0A; // '\n'

    reg [7:0] msg [0:3];
    reg [2:0] cnt = 3'd0;  // 0..4, number of bytes remaining

    wire       fifo_empty = (cnt == 3'd0);
    wire [7:0] fifo_data  = msg[0];
    wire       fifo_rd;

    always @(posedge clk) begin
        if (btn_press) begin
            msg[0] <= MSG0; msg[1] <= MSG1; msg[2] <= MSG2; msg[3] <= MSG3;
            cnt    <= 3'd4;
        end else if (fifo_rd && !fifo_empty) begin
            msg[0] <= msg[1]; msg[1] <= msg[2]; msg[2] <= msg[3];
            cnt    <= cnt - 3'd1;
        end
    end

    // ── SPI slave ─────────────────────────────────────────────────────────
    spi_slave spi_inst (
        .clk        (clk),
        .rst_n      (rst_n),
        .fifo_data  (fifo_data),
        .fifo_empty (fifo_empty),
        .fifo_rd    (fifo_rd),
        .spi_sck    (spi_sck),
        .spi_cs_n   (spi_cs_n),
        .spi_miso   (spi_miso)
    );

endmodule
