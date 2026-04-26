`timescale 1ns/1ps
`default_nettype none
// IEEE 802.3 Clause 22 MDIO master.
//
// MDC = clk / (2 * CLK_DIV).
// Caller must not assert req while busy=1.
// Tri-state MDIO is split into mdio_oe/mdio_out/mdio_in so the bidirectional
// pin can be assembled in the caller (e.g. assign mdio = oe ? out : 1'bz).
//
// Frame layout (64 bits, MSB-first):
//   [63:32] PRE  = 32'hFFFFFFFF
//   [31:30] SOF  = 2'b01
//   [29:28] OP   = 2'b01 (write) / 2'b10 (read)
//   [27:23] PHYAD[4:0]
//   [22:18] REGAD[4:0]
//   [17:16] TA   = 2'b10 (write) / released (read)
//   [15: 0] DATA
//
// Transmit: master drives bits 0-45, releases bus from bit 46 for reads.
// Receive:  master samples mdio_in on rising MDC edges for bits 48-63.

module mdio_master #(
    parameter CLK_DIV  = 12,   // MDC half-period in clk cycles → MDC ≈ clk/(2×CLK_DIV)
    parameter PHY_ADDR = 5'd0
) (
    input  wire        clk,
    input  wire        rst_n,

    output reg         mdc,
    output reg         mdio_oe,    // 1 = drive mdio_out onto pin
    output reg         mdio_out,
    input  wire        mdio_in,

    input  wire        req,        // 1-cycle pulse to begin transaction
    input  wire        wr,         // 1=write, 0=read
    input  wire [4:0]  reg_addr,
    input  wire [15:0] wdata,

    output reg         busy,
    output reg         done,       // 1-cycle pulse when transaction complete
    output reg  [15:0] rdata,
    output reg         rdata_valid // 1-cycle pulse with valid read data
);

    // ── MDC divider ──────────────────────────────────────────────────
    localparam HALF  = CLK_DIV;
    localparam DBITS = $clog2(HALF) + 1;

    reg [DBITS-1:0] div;

    wire tick      = busy && (div == HALF - 1);
    wire mdc_rise  = tick && !mdc;   // MDC about to go 0→1
    wire mdc_fall  = tick &&  mdc;   // MDC about to go 1→0

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)   begin div <= 0; mdc <= 0; end
        else if (busy) begin
            if (tick) begin div <= 0; mdc <= ~mdc; end
            else           div <= div + 1;
        end else           begin div <= 0; mdc <= 0; end
    end

    // ── Shift register & state ───────────────────────────────────────
    reg [63:0] sr;
    reg [6:0]  bit_cnt;   // 0..63, advanced on each rising MDC edge
    reg        is_read;

    // Master drives MDIO while bit_cnt < 46 (or always for writes).
    // bit 46 = first TA bit → release for reads.
    wire master_drives = !is_read || (bit_cnt < 7'd46);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 0; done <= 0;
            rdata <= 0; rdata_valid <= 0;
            mdio_oe <= 0; mdio_out <= 1;
            bit_cnt <= 0; sr <= 0; is_read <= 0;
        end else begin
            done        <= 0;
            rdata_valid <= 0;

            // ── Start transaction ────────────────────────────────────
            if (!busy && req) begin
                sr <= { 32'hFFFF_FFFF,
                        2'b01,
                        wr ? 2'b01 : 2'b10,
                        PHY_ADDR,
                        reg_addr,
                        wr ? 2'b10 : 2'b00,
                        wr ? wdata : 16'h0000 };
                is_read  <= !wr;
                bit_cnt  <= 0;
                busy     <= 1;
                mdio_oe  <= 1;
                mdio_out <= 1;   // first preamble bit (held before MDC starts)
            end

            if (busy) begin
                // Drive MDIO on falling MDC edge
                if (mdc_fall) begin
                    mdio_oe  <= master_drives;
                    mdio_out <= sr[63];
                    sr       <= {sr[62:0], 1'b1};
                end

                // Sample (reads) and advance counter on rising MDC edge
                if (mdc_rise) begin
                    if (is_read && bit_cnt >= 7'd48)
                        rdata <= {rdata[14:0], mdio_in};

                    if (bit_cnt == 7'd63) begin
                        busy        <= 0;
                        done        <= 1;
                        mdio_oe     <= 0;
                        rdata_valid <= is_read;
                    end else
                        bit_cnt <= bit_cnt + 7'd1;
                end
            end
        end
    end

endmodule
`default_nettype wire
