// Unit test: smi_slave
//
// Scenario 1 – Write control register (addr 0x00), read it back.
// Scenario 2 – Write MITM registers, verify outputs.
// Scenario 3 – Feed packet counters in, read via SMI at addr 0x04-0x0B.
`timescale 1ns/1ps

module tb_smi_slave;

    localparam CLK_PERIOD = 10;   // 100 MHz SMI clock (arbitrary for test)

    reg clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    reg rst_n = 0;
    initial #(CLK_PERIOD*3) rst_n = 1;

    // DUT
    reg  [5:0]  smi_sa    = 0;
    reg  [7:0]  smi_d_in  = 0;
    wire [7:0]  smi_d_out;
    wire        smi_d_oe;
    reg         smi_soe_n = 1;
    reg         smi_swe_n = 1;

    wire        sw_rst, mitm_en;
    wire [7:0]  mitm_byte_idx, mitm_match, mitm_replace;

    reg [31:0]  pkt_count_p1 = 32'hDEAD_BEEF;
    reg [31:0]  pkt_count_p2 = 32'hCAFE_1234;

    smi_slave dut (
        .clk_smi      (clk),
        .rst_n        (rst_n),
        .smi_sa       (smi_sa),
        .smi_d_in     (smi_d_in),
        .smi_d_out    (smi_d_out),
        .smi_d_oe     (smi_d_oe),
        .smi_soe_n    (smi_soe_n),
        .smi_swe_n    (smi_swe_n),
        .sw_rst       (sw_rst),
        .mitm_en      (mitm_en),
        .mitm_byte_idx(mitm_byte_idx),
        .mitm_match   (mitm_match),
        .mitm_replace (mitm_replace),
        .pkt_count_p1 (pkt_count_p1),
        .pkt_count_p2 (pkt_count_p2)
    );

    // ------------------------------------------------------------------
    // Waveform dump
    // ------------------------------------------------------------------
    initial begin
        $dumpfile("sim/tb_smi_slave.vcd");
        $dumpvars(0, tb_smi_slave);
    end

    // ------------------------------------------------------------------
    // Tasks: SMI write and read helpers
    // ------------------------------------------------------------------
    task smi_write;
        input [5:0]  addr;
        input [7:0]  data;
        begin
            @(posedge clk);
            smi_sa    <= addr;
            smi_d_in  <= data;
            smi_swe_n <= 0;           // assert write strobe
            @(posedge clk);
            @(posedge clk);
            smi_swe_n <= 1;           // deassert → triggers latch on rising edge
            @(posedge clk);
        end
    endtask

    task smi_read;
        input  [5:0]  addr;
        output [7:0]  result;
        begin
            @(posedge clk);
            smi_sa    <= addr;
            smi_soe_n <= 0;           // assert read strobe
            @(posedge clk);           // combinational output available
            result    = smi_d_out;    // sample
            smi_soe_n <= 1;
            @(posedge clk);
        end
    endtask

    // ------------------------------------------------------------------
    // Test sequence
    // ------------------------------------------------------------------
    integer errors;
    reg [7:0] rd;

    initial begin
        errors = 0;
        @(posedge rst_n);
        repeat(2) @(posedge clk);

        // --- Scenario 1: write control register ---
        $display("[%0t] Scenario 1: control register write/read", $time);
        smi_write(6'h00, 8'h02);  // mitm_en=1, sw_rst=0
        smi_read (6'h00, rd);
        if (rd !== 8'h02) begin $display("FAIL ctrl: got %h, want 02", rd); errors=errors+1; end
        else $display("PASS ctrl: read back 0x%h", rd);

        if (!mitm_en) begin $display("FAIL mitm_en output not set"); errors=errors+1; end

        // --- Scenario 2: MITM registers ---
        $display("[%0t] Scenario 2: MITM registers", $time);
        smi_write(6'h01, 8'd14);   // byte index 14
        smi_write(6'h02, 8'hAB);   // match
        smi_write(6'h03, 8'hCD);   // replace

        smi_read(6'h01, rd); if (rd !== 8'd14)  begin $display("FAIL idx: %h",rd);     errors=errors+1; end
        smi_read(6'h02, rd); if (rd !== 8'hAB)  begin $display("FAIL match: %h",rd);   errors=errors+1; end
        smi_read(6'h03, rd); if (rd !== 8'hCD)  begin $display("FAIL replace: %h",rd); errors=errors+1; end
        $display("PASS MITM registers");

        // --- Scenario 3: read packet counters ---
        $display("[%0t] Scenario 3: packet counters (P1=0xDEADBEEF)", $time);
        smi_read(6'h04, rd); if (rd !== 8'hEF) begin $display("FAIL cnt[0]: %h",rd); errors=errors+1; end
        smi_read(6'h05, rd); if (rd !== 8'hBE) begin $display("FAIL cnt[1]: %h",rd); errors=errors+1; end
        smi_read(6'h06, rd); if (rd !== 8'hAD) begin $display("FAIL cnt[2]: %h",rd); errors=errors+1; end
        smi_read(6'h07, rd); if (rd !== 8'hDE) begin $display("FAIL cnt[3]: %h",rd); errors=errors+1; end
        $display("PASS P1 counter bytes");

        // --- Summary ---
        if (errors == 0)
            $display("=== ALL TESTS PASSED ===");
        else
            $display("=== %0d FAILURES ===", errors);

        $finish;
    end

endmodule
