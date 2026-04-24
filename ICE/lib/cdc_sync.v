// Two-flop Clock Domain Crossing synchroniser
// Safe only for single-bit or Gray-coded multi-bit signals.
`timescale 1ns/1ps

module cdc_sync #(
    parameter WIDTH = 1
) (
    input  wire             clk_dst,
    input  wire             rst_n,
    input  wire [WIDTH-1:0] d,
    output reg  [WIDTH-1:0] q
);
    reg [WIDTH-1:0] meta;

    always @(posedge clk_dst or negedge rst_n) begin
        if (!rst_n) begin
            meta <= {WIDTH{1'b0}};
            q    <= {WIDTH{1'b0}};
        end else begin
            meta <= d;
            q    <= meta;
        end
    end
endmodule
