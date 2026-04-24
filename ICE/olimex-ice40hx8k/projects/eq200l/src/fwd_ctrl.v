// fwd_ctrl.v — Drain a forwarding FIFO into rmii_tx.
//
// FIFO format:  [len_h, len_l, data[0] … data[N-1]]
//
// Reads the 2-byte length header then feeds exactly len bytes to rmii_tx.
// rmii_tx consumes one byte every 8 clk cycles (100 Mbps RMII at 50 MHz),
// so we have plenty of time to fetch the next byte from the FWFT FIFO after
// each tx_ready pulse.
`timescale 1ns/1ps

module fwd_ctrl (
    input  wire       clk,
    input  wire       rst_n,

    // Forwarding FIFO read port (FWFT — rd_data valid whenever !rd_empty)
    input  wire [7:0] fifo_data,
    input  wire       fifo_empty,
    output reg        fifo_rd,

    // rmii_tx byte-stream interface
    output reg  [7:0] tx_data,
    output reg        tx_valid,
    output reg        tx_eof,
    input  wire       tx_ready    // 1-cycle pulse: byte consumed, load next
);
    localparam S_IDLE     = 3'd0;
    localparam S_LENH     = 3'd1;   // captured len_h, consuming len_l
    localparam S_LENL     = 3'd2;   // captured len_l, consuming first byte
    localparam S_TX       = 3'd3;   // streaming bytes to rmii_tx
    localparam S_TX_FETCH = 3'd4;   // 1-cycle wait after fifo_rd (FWFT latency)

    reg [2:0]  state;
    reg [10:0] len;      // total frame bytes
    reg [10:0] sent;     // bytes consumed by rmii_tx so far
    reg [7:0]  len_h_r;  // temporary storage for len_h

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            len      <= 0;
            sent     <= 0;
            len_h_r  <= 0;
            fifo_rd  <= 0;
            tx_data  <= 0;
            tx_valid <= 0;
            tx_eof   <= 0;
        end else begin
            fifo_rd <= 0;

            case (state)

                // ── Wait for a frame header in the FIFO ───────────────────
                S_IDLE: begin
                    tx_valid <= 0;
                    tx_eof   <= 0;
                    if (!fifo_empty) begin
                        len_h_r <= fifo_data;   // capture len_h (FWFT, valid now)
                        fifo_rd <= 1;            // advance to len_l
                        state   <= S_LENH;
                    end
                end

                // ── len_l now at FIFO head ─────────────────────────────────
                S_LENH: begin
                    len     <= {3'd0, len_h_r[2:0], fifo_data[7:0]};
                    fifo_rd <= 1;   // advance to first data byte
                    sent    <= 0;
                    state   <= S_LENL;
                end

                // ── First data byte now at FIFO head ──────────────────────
                S_LENL: begin
                    if (!fifo_empty) begin
                        tx_data  <= fifo_data;
                        tx_valid <= 1;
                        tx_eof   <= (len == 11'd1);
                        state    <= S_TX;
                    end
                end

                // ── Stream: hold tx_data until tx_ready ───────────────────
                S_TX: begin
                    if (tx_ready) begin
                        sent <= sent + 1'b1;
                        if (sent == len - 1'b1) begin
                            // Last byte consumed by rmii_tx
                            tx_valid <= 0;
                            tx_eof   <= 0;
                            state    <= S_IDLE;
                        end else begin
                            fifo_rd  <= 1;   // advance FIFO to next byte
                            state    <= S_TX_FETCH;
                        end
                    end
                end

                // ── 1-cycle wait for FWFT FIFO to present next byte ───────
                S_TX_FETCH: begin
                    tx_data <= fifo_data;
                    tx_eof  <= (sent == len - 1'b1);
                    state   <= S_TX;
                end

            endcase
        end
    end
endmodule
