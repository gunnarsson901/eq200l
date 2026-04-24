// RMII Transmitter – converts byte stream to 2-bit PHY dibit stream.
// Runs in the PHY's REF_CLK domain (50 MHz).
//
// Handshake:
//   Caller presents tx_data + tx_eof before/during tx_ready.
//   tx_ready goes high for 1 cycle each time a byte has been consumed.
//   Assert tx_valid to start a new frame; hold until tx_eof.
`timescale 1ns/1ps

module rmii_tx (
    input  wire       clk,
    input  wire       rst_n,
    // Byte-stream input
    input  wire [7:0] tx_data,
    input  wire       tx_valid, // high when frame data is available
    input  wire       tx_eof,   // set with last byte
    output reg        tx_ready, // pulses high each time a byte is consumed
    // RMII PHY pins (outputs from FPGA)
    output reg        txen,
    output reg  [1:0] txd
);

    localparam IDLE = 2'd0;
    localparam PRE  = 2'd1;   // send preamble + SFD
    localparam DATA = 2'd2;
    localparam IFG  = 2'd3;   // inter-frame gap (96 bits = 48 RMII cycles)

    reg [1:0]  state;
    reg [1:0]  dibit;         // dibit position within byte (0-3)
    reg [2:0]  pre_byte;      // preamble byte index (0-6 = 0x55, 7 = 0xD5)
    reg [5:0]  ifg_cnt;
    reg [7:0]  tx_reg;        // byte currently being shifted out
    reg        eof_lat;

    // Dibit helper
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

    wire [7:0] pre_data = (pre_byte < 3'd7) ? 8'h55 : 8'hD5;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= IDLE;
            dibit    <= 0;
            pre_byte <= 0;
            ifg_cnt  <= 0;
            tx_reg   <= 0;
            eof_lat  <= 0;
            txen     <= 0;
            txd      <= 0;
            tx_ready <= 0;
        end else begin
            tx_ready <= 0;

            case (state)
                // -------------------------------------------------------
                IDLE: begin
                    txen     <= 0;
                    txd      <= 0;
                    pre_byte <= 0;
                    dibit    <= 0;
                    if (tx_valid) begin
                        state <= PRE;
                    end
                end

                // -------------------------------------------------------
                PRE: begin
                    txen <= 1;
                    txd  <= dibit_of(pre_data, dibit);
                    dibit <= dibit + 1;

                    if (dibit == 2'd3) begin
                        if (pre_byte == 3'd7) begin
                            // Preamble+SFD done – grab first data byte
                            tx_reg  <= tx_data;
                            eof_lat <= tx_eof;
                            tx_ready <= 1;   // consumed preamble slot, caller's first byte loaded
                            dibit   <= 0;
                            state   <= DATA;
                        end else begin
                            pre_byte <= pre_byte + 1;
                            dibit    <= 0;
                        end
                    end
                end

                // -------------------------------------------------------
                DATA: begin
                    txen <= 1;
                    txd  <= dibit_of(tx_reg, dibit);
                    dibit <= dibit + 1;

                    if (dibit == 2'd3) begin
                        if (eof_lat) begin
                            // Last byte fully sent
                            txen    <= 0;
                            ifg_cnt <= 0;
                            state   <= IFG;
                        end else begin
                            // Load next byte
                            tx_reg   <= tx_data;
                            eof_lat  <= tx_eof;
                            tx_ready <= 1;
                            dibit    <= 0;
                        end
                    end
                end

                // -------------------------------------------------------
                IFG: begin
                    txen    <= 0;
                    txd     <= 0;
                    ifg_cnt <= ifg_cnt + 1;
                    if (ifg_cnt == 6'd47)   // 48 × 2 bits = 96 bits IFG
                        state <= IDLE;
                end
            endcase
        end
    end
endmodule
