// Formal stub for gf_mont_mult (black-boxed for chassis proofs)
module gf_mont_mult #(
  parameter int unsigned WIDTH = 8
) (
  input  logic             clk_i,
  input  logic             rst_ni,
  input  logic             valid_i,
  output logic             ready_o,
  input  logic [WIDTH-1:0] a_i,
  input  logic [WIDTH-1:0] b_i,
  input  logic [WIDTH-1:0] m_i,
  output logic             valid_o,
  input  logic             ready_i,
  output logic [WIDTH-1:0] p_o,
  output logic             idle_o
);
  assign ready_o = 1'b1;
  assign valid_o = 1'b0;
  assign p_o = '0;
  assign idle_o = 1'b1;
endmodule
