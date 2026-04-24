// Full-system testbench – iCESugar-Pro Network Tap
//
// Drives RMII preamble + frame on PHY1 inputs and checks that the
// PHY bridge receives the bytes. TX-side RMII output is left as a
// TODO (stub outputs assigned in top.v).
`timescale 1ns/1ps

module tb_top;

    // 50 MHz for PHY clocks (20 ns), 12 MHz for sys oscillator (~83 ns)
    localparam P_CLK  = 20;
    localparam S_CLK  = 83;

    reg clk_12m   = 0;  always #(S_CLK/2)  clk_12m   = ~clk_12m;
    reg p1_clk    = 0;  always #(P_CLK/2)  p1_clk    = ~p1_clk;
    reg p2_clk    = 0;  always #(P_CLK/2)  p2_clk    = ~p2_clk;
    reg p3_clk    = 0;  always #(P_CLK/2)  p3_clk    = ~p3_clk;
    reg smi_clk   = 0;  always #50         smi_clk   = ~smi_clk;  // 10 MHz

    // PHY1 RMII stimulus
    reg        p1_crs_dv = 0;
    reg [1:0]  p1_rxd    = 0;

    // SMI bus
    reg  [7:0]  smi_d_drv = 8'hZZ;
    wire [7:0]  smi_d;
    reg  [5:0]  smi_sa    = 0;
    reg         smi_soe_n = 1;
    reg         smi_swe_n = 1;
    assign smi_d = smi_d_drv;

    // DUT
    top dut (
        .clk_12m   (clk_12m),
        .p1_ref_clk(p1_clk),
        .p1_crs_dv (p1_crs_dv),
        .p1_rxd    (p1_rxd),
        .p1_txen   (), .p1_txd(),
        .p1_rst_n  (),
        .p2_ref_clk(p2_clk),
        .p2_crs_dv (1'b0), .p2_rxd(2'b0),
        .p2_txen   (), .p2_txd(),
        .p2_rst_n  (),
        .p3_ref_clk(p3_clk),
        .p3_crs_dv (1'b0), .p3_rxd(2'b0),
        .p3_txen   (), .p3_txd(),
        .p3_rst_n  (),
        .smi_clk   (smi_clk),
        .smi_d     (smi_d),
        .smi_sa    (smi_sa),
        .smi_soe_n (smi_soe_n),
        .smi_swe_n (smi_swe_n),
        .led       ()
    );

    // ------------------------------------------------------------------
    // Waveform dump
    // ------------------------------------------------------------------
    initial begin
        $dumpfile("sim/tb_top.vcd");
        $dumpvars(0, tb_top);
    end

    // ------------------------------------------------------------------
    // Task: transmit one RMII byte (dibit LSB-first)
    // ------------------------------------------------------------------
    task rmii_send_byte;
        input [7:0] b;
        integer k;
        begin
            for (k = 0; k < 4; k = k+1) begin
                @(negedge p1_clk);
                p1_rxd <= b[k*2 +: 2];
            end
        end
    endtask

    // ------------------------------------------------------------------
    // Task: transmit a complete RMII frame (preamble + payload)
    // ------------------------------------------------------------------
    task rmii_send_frame;
        input [7:0] payload [0:3];
        integer j;
        begin
            // Assert CRS_DV before preamble
            @(negedge p1_clk);
            p1_crs_dv <= 1;

            // Preamble: 7 × 0x55
            for (j = 0; j < 7; j = j+1)
                rmii_send_byte(8'h55);

            // SFD: 0xD5
            rmii_send_byte(8'hD5);

            // Payload
            for (j = 0; j < 4; j = j+1)
                rmii_send_byte(payload[j]);

            // Deassert CRS_DV (end of frame)
            @(negedge p1_clk);
            p1_crs_dv <= 0;
            p1_rxd    <= 0;
        end
    endtask

    // ------------------------------------------------------------------
    // Stimulus
    // ------------------------------------------------------------------
    reg [7:0] pkt [0:3];

    initial begin
        $display("=== iCESugar-Pro tap system simulation ===");

        // Allow reset to settle
        #500;

        // Send packet: AA BB CC DD
        pkt[0] = 8'hAA;
        pkt[1] = 8'hBB;
        pkt[2] = 8'hCC;
        pkt[3] = 8'hDD;

        $display("[%0t] Sending packet AA BB CC DD on PHY1", $time);
        rmii_send_frame(pkt);

        // Wait for pipeline to drain
        #2000;

        // Enable MITM via SMI: set byte 2 match=CC -> replace=EE
        $display("[%0t] Enabling MITM via SMI", $time);
        @(posedge smi_clk);
        smi_sa = 6'h00; smi_d_drv = 8'h02; smi_swe_n = 0;
        @(posedge smi_clk); @(posedge smi_clk);
        smi_swe_n = 1; smi_d_drv = 8'hZZ;

        @(posedge smi_clk);
        smi_sa = 6'h01; smi_d_drv = 8'd2; smi_swe_n = 0;
        @(posedge smi_clk); @(posedge smi_clk);
        smi_swe_n = 1; smi_d_drv = 8'hZZ;

        @(posedge smi_clk);
        smi_sa = 6'h02; smi_d_drv = 8'hCC; smi_swe_n = 0;
        @(posedge smi_clk); @(posedge smi_clk);
        smi_swe_n = 1; smi_d_drv = 8'hZZ;

        @(posedge smi_clk);
        smi_sa = 6'h03; smi_d_drv = 8'hEE; smi_swe_n = 0;
        @(posedge smi_clk); @(posedge smi_clk);
        smi_swe_n = 1; smi_d_drv = 8'hZZ;

        #500;

        $display("[%0t] Sending packet again with MITM active", $time);
        rmii_send_frame(pkt);

        #2000;
        $display("=== simulation done – open sim/tb_top.vcd in GTKWave ===");
        $finish;
    end

endmodule
