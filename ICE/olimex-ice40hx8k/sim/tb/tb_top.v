`timescale 1ns / 1ps

module tb_top;

    // 100 MHz clock -> 10 ns period
    localparam CLK_PERIOD = 10;

    reg        clk  = 0;
    reg        btn1 = 1;  // idle high (active low)
    reg        btn2 = 1;
    wire [7:0] led;

    // DUT
    top dut (
        .clk  (clk),
        .btn1 (btn1),
        .btn2 (btn2),
        .led  (led)
    );

    // Clock generation
    always #(CLK_PERIOD / 2) clk = ~clk;

    // Waveform dump
    initial begin
        $dumpfile("sim/waves.vcd");
        $dumpvars(0, tb_top);
    end

    // Stimulus
    initial begin
        $display("=== iCE40HX8K-EVB simulation start ===");

        // Run for 200 clock cycles as a quick sanity check.
        // Increase SIM_CYCLES in the Makefile to simulate longer.
        repeat (`SIM_CYCLES) @(posedge clk);

        $display("led = %08b", led);
        $display("=== done ===");
        $finish;
    end

endmodule
