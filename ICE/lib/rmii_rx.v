// RMII Receiver – converts 2-bit PHY dibit stream to byte stream.
// Runs in the PHY's REF_CLK domain (50 MHz).
//
//  Dibit timing per byte (LSB-first):
//   cycle 0 → bits [1:0]
//   cycle 1 → bits [3:2]
//   cycle 2 → bits [5:4]
//   cycle 3 → bits [7:6]
`timescale 1ns/1ps

module rmii_rx (
    input  wire       clk,      // PHY REF_CLK, 50 MHz
    input  wire       rst_n,
    // RMII PHY pins (inputs to FPGA)
    input  wire       crs_dv,   // Carrier Sense / Data Valid
    input  wire [1:0] rxd,
    // Byte-stream output
    output reg        rx_valid, // byte ready on rx_data
    output reg  [7:0] rx_data,
    output reg        rx_sof,   // asserted with first byte of frame
    output reg        rx_eof    // asserted with last byte of frame
);

    localparam IDLE     = 2'd0;
    localparam PREAMBLE = 2'd1;
    localparam DATA     = 2'd2;

    reg [1:0] state;
    reg [1:0] dibit;        // dibit position in current byte (0-3)
    reg [7:0] sreg;         // shift register
    reg       first_byte;

    // Dibit helper: extract 2 bits at position p from byte b
    function [1:0] dibit_of;
        input [7:0] b;
        input [1:0] p;
        case (p)
            2'd0: dibit_of = b[1:0];
            2'd1: dibit_of = b[3:2];
            2'd2: dibit_of = b[5:4];
            2'd3: dibit_of = b[7:6];
        endcase
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            dibit      <= 0;
            sreg       <= 0;
            rx_valid   <= 0;
            rx_data    <= 0;
            rx_sof     <= 0;
            rx_eof     <= 0;
            first_byte <= 1;
        end else begin
            // Default: deassert strobes
            rx_valid <= 0;
            rx_sof   <= 0;
            rx_eof   <= 0;

            case (state)
                // -------------------------------------------------------
                IDLE: begin
                    dibit      <= 0;
                    first_byte <= 1;
                    // Preamble starts with dibit 01
                    if (crs_dv && rxd == 2'b01)
                        state <= PREAMBLE;
                end

                // -------------------------------------------------------
                // Consume preamble dibits (01…01) until SFD last dibit (11)
                PREAMBLE: begin
                    if (!crs_dv) begin
                        state <= IDLE;
                    end else if (rxd == 2'b11) begin
                        // Last dibit of SFD (0xD5) detected
                        dibit <= 0;
                        sreg  <= 0;
                        state <= DATA;
                    end
                    // else: still 01 preamble dibits, keep consuming
                end

                // -------------------------------------------------------
                DATA: begin
                    if (!crs_dv) begin
                        // Frame ended mid-byte or on byte boundary
                        rx_valid <= 1;
                        rx_eof   <= 1;
                        rx_data  <= sreg;
                        state    <= IDLE;
                        first_byte <= 1;
                    end else begin
                        // Shift in LSB-first
                        sreg  <= {rxd, sreg[7:2]};
                        dibit <= dibit + 1;

                        if (dibit == 2'd3) begin
                            rx_valid   <= 1;
                            rx_data    <= {rxd, sreg[7:2]};
                            rx_sof     <= first_byte;
                            first_byte <= 0;
                            dibit      <= 0;
                        end
                    end
                end
            endcase
        end
    end
endmodule
