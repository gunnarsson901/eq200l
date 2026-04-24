// spi_slave.v — SPI mode-0 slave, streams bytes from a FWFT FIFO to Pi
//
// Protocol (mode 0: CPOL=0, CPHA=0, MSB first):
//   Pi holds CS low and clocks SCK.
//   Each rising SCK edge the Pi samples MISO.
//   FPGA shifts out the next FIFO byte; sends 0xFF when FIFO is empty.
//   MOSI is ignored (receive-only slave).
//
// Clock domains:
//   All SPI signals (sck, cs_n) are asynchronous to clk.
//   Two-FF synchronisers bring them into the 50 MHz domain.
`timescale 1ns/1ps

module spi_slave (
    input  wire       clk,        // 50 MHz system clock
    input  wire       rst_n,

    // FIFO read port (combinatorial/FWFT: rd_data valid whenever !rd_empty)
    input  wire [7:0] fifo_data,
    input  wire       fifo_empty,
    output reg        fifo_rd,    // one-cycle pulse to advance FIFO pointer

    // SPI interface
    input  wire       spi_sck,
    input  wire       spi_cs_n,
    output wire       spi_miso    // FPGA → Pi
);

    // ── Two-FF synchronisers ────────────────────────────────────────────────
    reg [1:0] sck_r;
    reg [1:0] cs_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sck_r <= 2'b00;
            cs_r  <= 2'b11;   // CS idles high
        end else begin
            sck_r <= {sck_r[0], spi_sck};
            cs_r  <= {cs_r[0],  spi_cs_n};
        end
    end

    // Edge detects (one clock wide)
    wire sck_fall = sck_r[1] & ~sck_r[0];   // falling SCK — shift next bit
    wire cs_fall  = cs_r[1]  & ~cs_r[0];    // CS just went low  — load first byte

    // ── Shift register ──────────────────────────────────────────────────────
    // Mode 0: MISO is set up BEFORE the first rising SCK.
    // We pre-load on CS assertion so bit7 is stable for the first rise.
    // We shift on the FALLING edge so the next bit is ready for the
    // following rising edge.

    reg [7:0] shreg  = 8'hFF;   // iCE40 cold-starts regs at 0; force 0xFF
    reg [2:0] bitcnt = 3'd0;

    assign spi_miso = shreg[7];   // MSB first, combinational

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shreg   <= 8'hFF;
            bitcnt  <= 3'd0;
            fifo_rd <= 1'b0;
        end else begin
            fifo_rd <= 1'b0;

            // CS asserted: pre-load first byte so bit7 is on MISO immediately
            if (cs_fall) begin
                shreg   <= fifo_empty ? 8'hFF : fifo_data;
                fifo_rd <= ~fifo_empty;
                bitcnt  <= 3'd0;
            end

            // Shift on falling SCK while CS is active
            if (sck_fall && !cs_r[1]) begin
                if (bitcnt == 3'd7) begin
                    // Finished one byte — load the next
                    shreg   <= fifo_empty ? 8'hFF : fifo_data;
                    fifo_rd <= ~fifo_empty;
                    bitcnt  <= 3'd0;
                end else begin
                    shreg  <= {shreg[6:0], 1'b1};
                    bitcnt <= bitcnt + 3'd1;
                end
            end
        end
    end

endmodule
