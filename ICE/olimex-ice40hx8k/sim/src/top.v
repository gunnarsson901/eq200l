// iCE40HX8K-EVB top-level module
// Board: Olimex iCE40HX8K-EVB
// FPGA:  Lattice iCE40HX8K-CT256
// CLK:   100 MHz oscillator

module top (
    input  wire       clk,    // 100 MHz oscillator
    input  wire       btn1,   // BTN1 (active low)
    input  wire       btn2,   // BTN2 (active low)
    output wire [7:0] led     // LED1..LED8 (active low on board)
);

    // 100 MHz -> toggle every 0.5 s => 50_000_000 cycles
    localparam CLK_HZ      = 100_000_000;
    localparam BLINK_HZ    = 1;
    localparam CTR_MAX     = CLK_HZ / (BLINK_HZ * 2) - 1;  // 49_999_999

    reg [25:0] ctr  = 0;
    reg [7:0]  leds = 8'hFF;  // all off (active-low)

    always @(posedge clk) begin
        if (ctr == CTR_MAX) begin
            ctr  <= 0;
            leds <= ~leds;   // toggle
        end else begin
            ctr <= ctr + 1;
        end
    end

    assign led = leds;

endmodule
