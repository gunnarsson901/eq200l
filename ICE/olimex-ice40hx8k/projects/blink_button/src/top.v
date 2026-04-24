// blink_button — LED blinks at ~1 Hz; hold button to keep it solid on.
//
// Pins (ICE40HX8K-CT256):
//   clk  J3  GBIN6/SYSCLK — external clock (see PCF)
//   led  F4  PIO3_06
//   btn  C2  PIO3_05  (active-low, pull-up in PCF)
//
// Clock: external on J3 (GBIN6).  SB_HFOSC is not available on HX8K in
// nextpnr-ice40; only UltraPlus (UP3K/UP5K) devices support it.
// Adjust CLK_HZ to match your actual clock source.

module top #(
    parameter CLK_HZ = 50_000_000  // LAN8720 REFCLK on J3
) (
    input  wire clk,              // external clock on J3/GBIN6
    output led,
    input  btn                    // active-low; 0 = pressed
);

// ── Synchronise button (active-high internally) ────────────────────────────
reg [1:0] btn_sr;
always @(posedge clk) btn_sr <= {btn_sr[0], ~btn};
wire btn_pressed = btn_sr[1];   // 1 = button held down

// ── 1 Hz blink (toggle every CLK_HZ/2 cycles) ────────────────────────────
localparam HALF = CLK_HZ / 2 - 1;
localparam CNT_W = 25;   // wide enough for up to ~67 MHz

reg [CNT_W-1:0] cnt;
reg             blink;

always @(posedge clk) begin
    if (cnt == HALF) begin
        cnt   <= 0;
        blink <= ~blink;
    end else
        cnt <= cnt + 1'b1;
end

// ── Output: held button → LED solid on; released → blink ──────────────────
assign led = btn_pressed ? 1'b1 : blink;

endmodule
