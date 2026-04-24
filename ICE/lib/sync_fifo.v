// Synchronous FIFO with combinatorial read data.
//
// Parameters:
//   DATA_W – data width  (default 8)
//   DEPTH  – depth, must be a power of 2  (default 2048)
//   ADDR_W – log2(DEPTH)                  (default 11)
//
// rd_data is combinatorial (mem[rd_ptr]) — valid whenever !rd_empty.
// Yosys infers the mem[] array as Block RAM on iCE40 when DEPTH >= 256.
`timescale 1ns/1ps

module sync_fifo #(
    parameter DATA_W = 8,
    parameter DEPTH  = 2048,
    parameter ADDR_W = 11
) (
    input  wire              clk,
    input  wire              rst_n,
    // Write port
    input  wire              wr_en,
    input  wire [DATA_W-1:0] wr_data,
    output wire              wr_full,
    // Read port
    input  wire              rd_en,
    output wire [DATA_W-1:0] rd_data,
    output wire              rd_empty
);

    // Storage — synthesised as EBR on iCE40
    reg [DATA_W-1:0] mem [0:DEPTH-1];

    // Pointers: one extra bit distinguishes full from empty
    reg [ADDR_W:0] wr_ptr;
    reg [ADDR_W:0] rd_ptr;

    assign wr_full  = (wr_ptr[ADDR_W] != rd_ptr[ADDR_W]) &&
                      (wr_ptr[ADDR_W-1:0] == rd_ptr[ADDR_W-1:0]);
    assign rd_empty = (wr_ptr == rd_ptr);

    // Combinatorial read — latency 0
    assign rd_data  = mem[rd_ptr[ADDR_W-1:0]];

    // Write
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 0;
        end else begin
            if (wr_en && !wr_full) begin
                mem[wr_ptr[ADDR_W-1:0]] <= wr_data;
                wr_ptr <= wr_ptr + 1'b1;
            end
        end
    end

    // Read
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= 0;
        end else begin
            if (rd_en && !rd_empty)
                rd_ptr <= rd_ptr + 1'b1;
        end
    end

endmodule
