// Formal stub: gf_engine_if (Yosys has no SV interface support)
// Empty module — engines are black-boxed for chassis proofs.
module gf_engine_if
  import gf_pkg::*;
#(
  parameter int unsigned WIDTH = 8,
  parameter int unsigned EXP_W = 8
) (
  input logic clk_i,
  input logic rst_ni
);
endmodule
