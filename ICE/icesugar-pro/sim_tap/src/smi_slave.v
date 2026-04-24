// SMI Slave – exposes a register file to the Raspberry Pi CM4.
//
// The CM4's BCM2711 SMI peripheral treats the FPGA as an external SRAM.
// Signals:
//   smi_sa[5:0]   – 6-bit address (64 byte-wide registers)
//   smi_d[7:0]    – bidirectional 8-bit data bus (modelled as separate in/out here)
//   smi_soe_n     – read strobe (active low)
//   smi_swe_n     – write strobe (active low)
//
// Register map:
//   0x00  Control:   [0]=sw_rst  [1]=mitm_en
//   0x01  mitm_byte_idx
//   0x02  mitm_match
//   0x03  mitm_replace
//   0x04  pkt_count_p1[7:0]
//   0x05  pkt_count_p1[15:8]
//   0x06  pkt_count_p1[23:16]
//   0x07  pkt_count_p1[31:24]
//   0x08  pkt_count_p2[7:0]
//   0x09  pkt_count_p2[15:8]
//   0x0A  pkt_count_p2[23:16]
//   0x0B  pkt_count_p2[31:24]
`timescale 1ns/1ps

module smi_slave (
    input  wire        clk_smi,   // SMI bus clock (from CM4)
    input  wire        rst_n,

    // SMI bus
    input  wire [5:0]  smi_sa,
    input  wire [7:0]  smi_d_in,  // data from CM4 (write)
    output reg  [7:0]  smi_d_out, // data to CM4 (read)
    output reg         smi_d_oe,  // drive the bus when high
    input  wire        smi_soe_n, // read strobe (active low)
    input  wire        smi_swe_n, // write strobe (active low)

    // Control outputs (to phy_bridge via CDC in top.v)
    output reg         sw_rst,
    output reg         mitm_en,
    output reg  [7:0]  mitm_byte_idx,
    output reg  [7:0]  mitm_match,
    output reg  [7:0]  mitm_replace,

    // Statistics inputs (from phy_bridge via CDC in top.v)
    input  wire [31:0] pkt_count_p1,
    input  wire [31:0] pkt_count_p2
);

    // ------------------------------------------------------------------
    // Write path – latch register on rising edge of write strobe
    // ------------------------------------------------------------------
    reg smi_swe_n_prev;

    always @(posedge clk_smi or negedge rst_n) begin
        if (!rst_n) begin
            sw_rst        <= 0;
            mitm_en       <= 0;
            mitm_byte_idx <= 0;
            mitm_match    <= 0;
            mitm_replace  <= 0;
            smi_swe_n_prev <= 1;
        end else begin
            smi_swe_n_prev <= smi_swe_n;
            sw_rst         <= 0;   // auto-clear after one cycle

            // Detect rising edge of write strobe (end of write)
            if (smi_swe_n && !smi_swe_n_prev) begin
                case (smi_sa)
                    6'h00: begin
                        sw_rst  <= smi_d_in[0];
                        mitm_en <= smi_d_in[1];
                    end
                    6'h01: mitm_byte_idx <= smi_d_in;
                    6'h02: mitm_match    <= smi_d_in;
                    6'h03: mitm_replace  <= smi_d_in;
                    // 0x04-0x0B are read-only statistics
                    default: ; // ignore writes to unknown addresses
                endcase
            end
        end
    end

    // ------------------------------------------------------------------
    // Read path – combinational, gated by smi_soe_n
    // ------------------------------------------------------------------
    always @(*) begin
        smi_d_oe  = !smi_soe_n;
        smi_d_out = 8'h00;

        if (!smi_soe_n) begin
            case (smi_sa)
                6'h00: smi_d_out = {6'b0, mitm_en, sw_rst};
                6'h01: smi_d_out = mitm_byte_idx;
                6'h02: smi_d_out = mitm_match;
                6'h03: smi_d_out = mitm_replace;
                6'h04: smi_d_out = pkt_count_p1[7:0];
                6'h05: smi_d_out = pkt_count_p1[15:8];
                6'h06: smi_d_out = pkt_count_p1[23:16];
                6'h07: smi_d_out = pkt_count_p1[31:24];
                6'h08: smi_d_out = pkt_count_p2[7:0];
                6'h09: smi_d_out = pkt_count_p2[15:8];
                6'h0A: smi_d_out = pkt_count_p2[23:16];
                6'h0B: smi_d_out = pkt_count_p2[31:24];
                default: smi_d_out = 8'hFF;
            endcase
        end
    end

endmodule
