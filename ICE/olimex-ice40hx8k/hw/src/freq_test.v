// freq_test.v — drive 7 divided-clock outputs
//
// clock input : R11 (SCK/PIO2_48) ← Pi GPIO11 (SPI0 CLK, PGM1 connector pin 9)
//               Pi bit-bangs ~1 kHz square wave on GPIO11 after upload.
//               No external oscillator or LAN8720 required.
//
// outputs on J2 connector  (BGA ball → pi03 net → divided frequency @ 1 kHz source)
//
//   Ball  pi03     Frequency
//   D2    pi03_07  500  Hz  (/2)
//   G5    pi03_08  250  Hz  (/4)
//   D1    pi03_09  125  Hz  (/8)
//   G4    pi03_10   62  Hz  (/16)
//   E3    pi03_11   31  Hz  (/32)
//   H5    pi03_12   15  Hz  (/64)
//   H2    pi03_23    7  Hz  (/128)
//
module freq_test (
    input  wire clk_pin,    // R11 / SCK / Pi GPIO11 (~1 kHz square wave)
    output wire out_div2,
    output wire out_div4,
    output wire out_div8,
    output wire out_div16,
    output wire out_div32,
    output wire out_div64,
    output wire out_div128,
    output wire led1,
    output wire led2,
    output wire test_out    // ~3.9 Hz pulse on J4 → Pi GPIO15
);

// R11 is not a GBIN pin — use directly, nextpnr routes through local fabric
reg [26:0] cnt = 27'd0;

always @(posedge clk_pin)
    cnt <= cnt + 1'b1;

assign out_div2   = cnt[0];   //  500 Hz
assign out_div4   = cnt[1];   //  250 Hz
assign out_div8   = cnt[2];   //  125 Hz
assign out_div16  = cnt[3];   //   62 Hz
assign out_div32  = cnt[4];   //   31 Hz
assign out_div64  = cnt[5];   //   15 Hz
assign out_div128 = cnt[6];   //    7 Hz

// LED blink at ~1 kHz source: cnt[9]=~1 Hz, cnt[8]=~2 Hz
assign led1 = cnt[9];    // ~0.98 Hz — visible blink confirms FPGA counter running
assign led2 = cnt[8];    // ~1.95 Hz
assign test_out = cnt[7]; // ~3.9 Hz → J4 → Pi GPIO15 (readable via raspi-gpio)

endmodule
