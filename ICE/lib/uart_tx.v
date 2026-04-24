// UART Transmitter — 8N1, configurable baud rate.
//
// Handshake:
//   Caller drives valid=1 with data stable.
//   ready=1 means the transmitter is idle and will accept a byte.
//   A byte is accepted (and ready deasserts) on the rising clock edge
//   when both valid and ready are high.
//
// Example: 1 Mbaud @ 50 MHz → DIV = 50 (cycles per bit).
`timescale 1ns/1ps

module uart_tx #(
    parameter CLK_HZ = 50_000_000,
    parameter BAUD   = 1_000_000
) (
    input  wire       clk,
    input  wire       rst_n,
    // Byte input
    input  wire [7:0] data,
    input  wire       valid,
    output reg        ready,
    // UART output (idle high)
    output reg        tx
);

    localparam DIV = CLK_HZ / BAUD;   // cycles per UART bit

    // DIV counter width: clog2(DIV)
    localparam CDIV = (DIV <= 2)   ? 1 :
                      (DIV <= 4)   ? 2 :
                      (DIV <= 8)   ? 3 :
                      (DIV <= 16)  ? 4 :
                      (DIV <= 32)  ? 5 :
                      (DIV <= 64)  ? 6 :
                      (DIV <= 128) ? 7 :
                      (DIV <= 256) ? 8 :
                      (DIV <= 512) ? 9 : 10;

    // Shift register: {stop=1, d7..d0, start=0} = 10 bits
    reg [9:0]       shift;
    reg [CDIV-1:0]  baud_cnt;
    reg [3:0]       bit_cnt;   // 0-9 (10 bits per frame)
    reg             busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx       <= 1'b1;
            ready    <= 1'b1;
            busy     <= 1'b0;
            baud_cnt <= 0;
            bit_cnt  <= 0;
            shift    <= 10'h3FF;
        end else begin
            if (!busy) begin
                ready <= 1'b1;
                tx    <= 1'b1;
                if (valid) begin
                    // Frame: start(0) | d0..d7 | stop(1)   LSB first
                    shift    <= {1'b1, data[7:0], 1'b0};
                    busy     <= 1'b1;
                    ready    <= 1'b0;
                    baud_cnt <= 0;
                    bit_cnt  <= 0;
                end
            end else begin
                // Drive the current bit
                tx <= shift[0];

                if (baud_cnt == DIV - 1) begin
                    baud_cnt <= 0;
                    shift    <= {1'b1, shift[9:1]};  // shift right, fill with 1

                    if (bit_cnt == 4'd9) begin
                        // Stop bit just completed
                        busy <= 1'b0;
                    end else begin
                        bit_cnt <= bit_cnt + 1'b1;
                    end
                end else begin
                    baud_cnt <= baud_cnt + 1'b1;
                end
            end
        end
    end

endmodule
