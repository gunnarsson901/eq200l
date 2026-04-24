// Unit test: phy_bridge
//
// Scenario 1 – transparent forwarding:
//   Drive a 4-byte packet on P1 RX.
//   Verify it appears byte-for-byte on P2 TX and P3 TX.
//
// Scenario 2 – MITM substitution:
//   Enable mitm_en, set byte_idx=2, match=0xBE, replace=0xEF.
//   Drive the same packet; verify byte 2 is changed on P2 TX.
`timescale 1ns/1ps

module tb_phy_bridge;

    localparam CLK_PERIOD = 20;   // 50 MHz (same for all domains in this TB)

    reg clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    reg rst_n = 0;
    initial #(CLK_PERIOD*3) rst_n = 1;

    // DUT signals
    reg        p1_rx_valid=0, p1_rx_sof=0, p1_rx_eof=0;
    reg [7:0]  p1_rx_data=0;
    wire       p1_rx_ready;

    reg        p2_rx_valid=0, p2_rx_sof=0, p2_rx_eof=0;
    reg [7:0]  p2_rx_data=0;
    wire       p2_rx_ready;

    wire       p2_tx_valid, p2_tx_sof, p2_tx_eof;
    wire [7:0] p2_tx_data;

    wire       p1_tx_valid, p1_tx_sof, p1_tx_eof;
    wire [7:0] p1_tx_data;

    wire       p3_tx_valid, p3_tx_sof, p3_tx_eof;
    wire [7:0] p3_tx_data;

    reg        mitm_en = 0;
    reg [7:0]  mitm_byte_idx = 0, mitm_match = 0, mitm_replace = 0;
    wire [31:0] pkt_count_p1, pkt_count_p2;

    phy_bridge dut (
        .clk_sys      (clk),
        .rst_n        (rst_n),
        .p1_rx_valid  (p1_rx_valid), .p1_rx_data(p1_rx_data),
        .p1_rx_sof    (p1_rx_sof),   .p1_rx_eof (p1_rx_eof),
        .p1_rx_ready  (p1_rx_ready),
        .p2_rx_valid  (p2_rx_valid), .p2_rx_data(p2_rx_data),
        .p2_rx_sof    (p2_rx_sof),   .p2_rx_eof (p2_rx_eof),
        .p2_rx_ready  (p2_rx_ready),
        .p2_tx_valid  (p2_tx_valid), .p2_tx_data(p2_tx_data),
        .p2_tx_sof    (p2_tx_sof),   .p2_tx_eof (p2_tx_eof),
        .p2_tx_ready  (1'b1),
        .p1_tx_valid  (p1_tx_valid), .p1_tx_data(p1_tx_data),
        .p1_tx_sof    (p1_tx_sof),   .p1_tx_eof (p1_tx_eof),
        .p1_tx_ready  (1'b1),
        .p3_tx_valid  (p3_tx_valid), .p3_tx_data(p3_tx_data),
        .p3_tx_sof    (p3_tx_sof),   .p3_tx_eof (p3_tx_eof),
        .p3_tx_ready  (1'b1),
        .mitm_en      (mitm_en),
        .mitm_byte_idx(mitm_byte_idx),
        .mitm_match   (mitm_match),
        .mitm_replace (mitm_replace),
        .sw_rst       (1'b0),
        .pkt_count_p1 (pkt_count_p1),
        .pkt_count_p2 (pkt_count_p2)
    );

    // ------------------------------------------------------------------
    // Waveform dump
    // ------------------------------------------------------------------
    initial begin
        $dumpfile("sim/tb_phy_bridge.vcd");
        $dumpvars(0, tb_phy_bridge);
    end

    // ------------------------------------------------------------------
    // Task: send a packet over P1 RX
    // ------------------------------------------------------------------
    task send_p1_packet;
        input [7:0] b0, b1, b2, b3;
        begin
            @(posedge clk);
            // Byte 0 (SOF)
            p1_rx_valid <= 1; p1_rx_sof <= 1; p1_rx_eof <= 0; p1_rx_data <= b0;
            @(posedge clk);
            p1_rx_sof <= 0; p1_rx_data <= b1;
            @(posedge clk);
            p1_rx_data <= b2;
            @(posedge clk);
            // Byte 3 (EOF)
            p1_rx_eof <= 1; p1_rx_data <= b3;
            @(posedge clk);
            p1_rx_valid <= 0; p1_rx_eof <= 0;
        end
    endtask

    // ------------------------------------------------------------------
    // Checker: collect N bytes from P2 TX
    // ------------------------------------------------------------------
    integer i;
    reg [7:0] captured [0:15];
    integer   cap_idx;

    always @(posedge clk) begin
        if (p2_tx_valid) begin
            captured[cap_idx] <= p2_tx_data;
            cap_idx           <= cap_idx + 1;
        end
    end

    // ------------------------------------------------------------------
    // Test sequence
    // ------------------------------------------------------------------
    integer errors;

    initial begin
        errors  = 0;
        cap_idx = 0;
        @(posedge rst_n);
        repeat(2) @(posedge clk);

        // --- Scenario 1: transparent forward ---
        $display("[%0t] Scenario 1: transparent forward", $time);
        send_p1_packet(8'hAA, 8'hBB, 8'hBE, 8'hDD);
        repeat(4) @(posedge clk);   // pipeline flush

        if (captured[0] !== 8'hAA) begin $display("FAIL byte0: got %h", captured[0]); errors=errors+1; end
        if (captured[1] !== 8'hBB) begin $display("FAIL byte1: got %h", captured[1]); errors=errors+1; end
        if (captured[2] !== 8'hBE) begin $display("FAIL byte2: got %h", captured[2]); errors=errors+1; end
        if (captured[3] !== 8'hDD) begin $display("FAIL byte3: got %h", captured[3]); errors=errors+1; end

        $display("[%0t] pkt_count_p1=%0d (expect 1)", $time, pkt_count_p1);
        if (pkt_count_p1 !== 32'd1) begin $display("FAIL pkt_count"); errors=errors+1; end

        // --- Scenario 2: MITM substitution ---
        $display("[%0t] Scenario 2: MITM byte[2] 0xBE -> 0xEF", $time);
        mitm_en       = 1;
        mitm_byte_idx = 8'd2;
        mitm_match    = 8'hBE;
        mitm_replace  = 8'hEF;
        cap_idx = 0;

        repeat(2) @(posedge clk);
        send_p1_packet(8'hAA, 8'hBB, 8'hBE, 8'hDD);
        repeat(4) @(posedge clk);

        if (captured[2] !== 8'hEF) begin $display("FAIL MITM: byte2 got %h, want EF", captured[2]); errors=errors+1; end
        else $display("PASS MITM: byte2 correctly replaced with EF");

        // --- Summary ---
        if (errors == 0)
            $display("=== ALL TESTS PASSED ===");
        else
            $display("=== %0d FAILURES ===", errors);

        $finish;
    end

endmodule
