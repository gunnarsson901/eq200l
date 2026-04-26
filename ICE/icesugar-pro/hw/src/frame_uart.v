`timescale 1ns/1ps
// Reads a byte-stream (SOF/EOF flagged) and outputs UART frames.
//
// Wire format:  0xAA 0x55 | <data bytes> | 0xAA 0x56
// Byte-stuff:  0xAA in data → 0xAA 0x00  (so receiver can resync)
//
// Handshake: in_ready pulses 1 for exactly one cycle to consume a byte.
// Upstream should present stable in_data/in_sof/in_eof when in_valid=1.
`default_nettype none

module frame_uart #(
    parameter CLK_HZ = 25_000_000,
    parameter BAUD   = 1_000_000
) (
    input  wire       clk,
    input  wire       rst_n,

    // Byte stream input (FWFT: data valid when in_valid=1)
    input  wire       in_valid,
    input  wire [7:0] in_data,
    input  wire       in_sof,
    input  wire       in_eof,
    input  wire       in_dir,     // 0=Pi→Router (SOF2=0x55), 1=Router→Pi (SOF2=0x57)
    output wire       in_ready,   // consume current byte

    // UART
    output wire       tx,
    input  wire       rx          // passed through to host (future use)
);

    // ------------------------------------------------------------------
    // UART TX instance
    // ------------------------------------------------------------------
    wire        utx_ready;
    reg  [7:0]  utx_data;
    reg         utx_valid;

    uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) utx (
        .clk   (clk),
        .rst_n (rst_n),
        .data  (utx_data),
        .valid (utx_valid),
        .ready (utx_ready),
        .tx    (tx)
    );

    // ------------------------------------------------------------------
    // Frame serialiser state machine
    // ------------------------------------------------------------------
    localparam FS_IDLE     = 3'd0;
    localparam FS_SOF1     = 3'd1;   // send 0xAA
    localparam FS_SOF2     = 3'd2;   // send 0x55
    localparam FS_LOAD     = 3'd3;   // wait for/consume next byte
    localparam FS_SEND     = 3'd4;   // send latched byte (or 0xAA escape prefix)
    localparam FS_ESC      = 3'd5;   // send 0x00 (escape suffix)
    localparam FS_EOF1     = 3'd6;   // send 0xAA
    localparam FS_EOF2     = 3'd7;   // send 0x56

    reg [2:0] state;
    reg [7:0] latch_data;
    reg       latch_eof;
    reg       latch_dir;  // direction latched at SOF
    reg       escaping;   // 1 = current SEND is the 0xAA prefix of an escape

    // Consume a byte from upstream when we're in LOAD and data is ready
    assign in_ready = (state == FS_LOAD) && in_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= FS_IDLE;
            utx_valid  <= 1'b0;
            utx_data   <= 8'h00;
            latch_data <= 8'h00;
            latch_eof  <= 1'b0;
            latch_dir  <= 1'b0;
            escaping   <= 1'b0;
        end else begin
            utx_valid <= 1'b0;  // default: nothing to send

            case (state)

                // --------------------------------------------------
                FS_IDLE: begin
                    if (in_valid && in_sof) begin
                        latch_dir <= in_dir;
                        state     <= FS_SOF1;
                    end
                end

                // --------------------------------------------------
                FS_SOF1: begin
                    utx_data  <= 8'hAA;
                    utx_valid <= 1'b1;
                    if (utx_ready) state <= FS_SOF2;
                end

                // --------------------------------------------------
                FS_SOF2: begin
                    utx_data  <= latch_dir ? 8'h57 : 8'h55;
                    utx_valid <= 1'b1;
                    if (utx_ready) state <= FS_LOAD;
                end

                // --------------------------------------------------
                FS_LOAD: begin
                    if (in_valid) begin
                        latch_data <= in_data;
                        latch_eof  <= in_eof;
                        escaping   <= (in_data == 8'hAA);
                        state      <= FS_SEND;
                    end
                end

                // --------------------------------------------------
                FS_SEND: begin
                    // Send either the raw byte or 0xAA (escape prefix).
                    utx_data  <= escaping ? 8'hAA : latch_data;
                    utx_valid <= 1'b1;
                    if (utx_ready) begin
                        if (escaping) begin
                            state <= FS_ESC;
                        end else if (latch_eof) begin
                            state <= FS_EOF1;
                        end else begin
                            state <= FS_LOAD;
                        end
                    end
                end

                // --------------------------------------------------
                FS_ESC: begin
                    utx_data  <= 8'h00;
                    utx_valid <= 1'b1;
                    if (utx_ready) begin
                        if (latch_eof) state <= FS_EOF1;
                        else           state <= FS_LOAD;
                    end
                end

                // --------------------------------------------------
                FS_EOF1: begin
                    utx_data  <= 8'hAA;
                    utx_valid <= 1'b1;
                    if (utx_ready) state <= FS_EOF2;
                end

                // --------------------------------------------------
                FS_EOF2: begin
                    utx_data  <= 8'h56;
                    utx_valid <= 1'b1;
                    if (utx_ready) state <= FS_IDLE;
                end

            endcase
        end
    end

endmodule
`default_nettype wire
