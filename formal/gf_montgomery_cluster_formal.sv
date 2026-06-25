// Formal-only stub for gf_montgomery_cluster (Yosys compat: no unpacked arrays)
// Black-boxed for chassis property proofs — multiplier correctness proven separately.
module gf_montgomery_cluster #(
  parameter int unsigned WIDTH           = 8,
  parameter int unsigned NUM_MULTIPLIERS = 1
) (
  input  logic             clk_i,
  input  logic             rst_ni,
  input  logic             req_valid_i,
  output logic             req_ready_o,
  input  logic [WIDTH-1:0] req_a_i,
  input  logic [WIDTH-1:0] req_b_i,
  input  logic [WIDTH-1:0] req_m_i,
  output logic             rsp_valid_o,
  input  logic             rsp_ready_i,
  output logic [WIDTH-1:0] rsp_p_o,
  output logic             idle_o
);
endmodule
