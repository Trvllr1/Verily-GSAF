// Formal stubs for engine wrappers (Yosys can't parse SV interfaces)
// All ports flattened to plain logic for chassis property proofs.

module gf_modexp_engine_wrapper #(
  parameter int unsigned WIDTH          = 8,
  parameter int unsigned EXP_BLIND_BITS = 0
) (
  input  logic clk_i, input logic rst_ni,
  input  logic engine_if_cmd_valid, output logic engine_if_cmd_ready,
  input  logic [3:0] engine_if_cmd_opcode,
  input  logic [7:0] engine_if_cmd_txn_id,
  input  logic [WIDTH-1:0] engine_if_cmd_base,
  input  logic [WIDTH+EXP_BLIND_BITS-1:0] engine_if_cmd_exp,
  input  logic [WIDTH-1:0] engine_if_cmd_m,
  output logic engine_if_rsp_valid, input logic engine_if_rsp_ready,
  output logic [WIDTH-1:0] engine_if_rsp_result,
  output logic [2:0] engine_if_rsp_status,
  output logic [7:0] engine_if_rsp_txn_id,
  output logic engine_if_engine_idle,
  output logic mul_req_valid_o, input logic mul_req_ready_i,
  output logic [WIDTH-1:0] mul_a_o, mul_b_o, mul_m_o,
  input logic mul_rsp_valid_i, output logic mul_rsp_ready_o,
  input logic [WIDTH-1:0] mul_p_i
);
  assign engine_if_cmd_ready = 1'b1;
  assign engine_if_rsp_valid = 1'b0;
  assign engine_if_rsp_result = '0;
  assign engine_if_rsp_status = gf_pkg::STATUS_OK;
  assign engine_if_rsp_txn_id = '0;
  assign engine_if_engine_idle = 1'b1;
  assign mul_req_valid_o = 1'b0;
  assign mul_a_o = '0; assign mul_b_o = '0; assign mul_m_o = '0;
  assign mul_rsp_ready_o = 1'b1;
endmodule

module gf_modinv_engine_wrapper #(
  parameter int unsigned WIDTH = 8
) (
  input  logic clk_i, input logic rst_ni,
  input  logic engine_if_cmd_valid, output logic engine_if_cmd_ready,
  input  logic [3:0] engine_if_cmd_opcode,
  input  logic [7:0] engine_if_cmd_txn_id,
  input  logic [WIDTH-1:0] engine_if_cmd_base, engine_if_cmd_exp, engine_if_cmd_m,
  output logic engine_if_rsp_valid, input logic engine_if_rsp_ready,
  output logic [WIDTH-1:0] engine_if_rsp_result,
  output logic [2:0] engine_if_rsp_status,
  output logic [7:0] engine_if_rsp_txn_id,
  output logic engine_if_engine_idle
);
  assign engine_if_cmd_ready = 1'b1;
  assign engine_if_rsp_valid = 1'b0;
  assign engine_if_rsp_result = '0;
  assign engine_if_rsp_status = gf_pkg::STATUS_OK;
  assign engine_if_rsp_txn_id = '0;
  assign engine_if_engine_idle = 1'b1;
endmodule

module gf_pqc_engine_wrapper #(
  parameter int unsigned WIDTH = 8, parameter int unsigned N = 256,
  parameter int unsigned Q = 8380417
) (
  input  logic clk_i, input logic rst_ni,
  input  logic engine_if_cmd_valid, output logic engine_if_cmd_ready,
  input  logic [3:0] engine_if_cmd_opcode,
  input  logic [7:0] engine_if_cmd_txn_id,
  input  logic [WIDTH-1:0] engine_if_cmd_base, engine_if_cmd_exp, engine_if_cmd_m,
  output logic engine_if_rsp_valid, input logic engine_if_rsp_ready,
  output logic [WIDTH-1:0] engine_if_rsp_result,
  output logic [2:0] engine_if_rsp_status,
  output logic [7:0] engine_if_rsp_txn_id,
  output logic engine_if_engine_idle,
  output logic mul_req_valid_o, input logic mul_req_ready_i,
  output logic [WIDTH-1:0] mul_a_o, mul_b_o, mul_m_o,
  input logic mul_rsp_valid_i, output logic mul_rsp_ready_o,
  input logic [WIDTH-1:0] mul_p_i,
  output logic coeff_wr_en,
  output logic [$clog2(N)-1:0] coeff_wr_addr,
  output logic [WIDTH-1:0] coeff_wr_data,
  output logic coeff_rd_en,
  output logic [$clog2(N)-1:0] coeff_rd_addr,
  input logic [WIDTH-1:0] coeff_rd_data
);
  assign engine_if_cmd_ready = 1'b1;
  assign engine_if_rsp_valid = 1'b0;
  assign engine_if_rsp_result = '0;
  assign engine_if_rsp_status = gf_pkg::STATUS_OK;
  assign engine_if_rsp_txn_id = '0;
  assign engine_if_engine_idle = 1'b1;
  assign mul_req_valid_o = 1'b0;
  assign mul_a_o = '0; assign mul_b_o = '0; assign mul_m_o = '0;
  assign mul_rsp_ready_o = 1'b1;
  assign coeff_wr_en = 1'b0;
  assign coeff_wr_addr = '0;
  assign coeff_wr_data = '0;
  assign coeff_rd_en = 1'b0;
  assign coeff_rd_addr = '0;
endmodule

module gf_rsa_crt_engine_wrapper #(
  parameter int unsigned WIDTH = 8, parameter int unsigned EXP_W = 8
) (
  input  logic clk_i, input logic rst_ni,
  input  logic engine_if_cmd_valid, output logic engine_if_cmd_ready,
  input  logic [3:0] engine_if_cmd_opcode,
  input  logic [7:0] engine_if_cmd_txn_id,
  input  logic [WIDTH-1:0] engine_if_cmd_base, engine_if_cmd_exp, engine_if_cmd_m,
  output logic engine_if_rsp_valid, input logic engine_if_rsp_ready,
  output logic [WIDTH-1:0] engine_if_rsp_result,
  output logic [2:0] engine_if_rsp_status,
  output logic [7:0] engine_if_rsp_txn_id,
  output logic engine_if_engine_idle,
  input  logic [WIDTH-1:0] rsa_p_i, rsa_q_i, rsa_dp_i, rsa_dq_i, rsa_qinv_i,
  output logic mul_req_valid_o, input logic mul_req_ready_i,
  output logic [WIDTH-1:0] mul_a_o, mul_b_o, mul_m_o,
  input logic mul_rsp_valid_i, output logic mul_rsp_ready_o,
  input logic [WIDTH-1:0] mul_p_i
);
  assign engine_if_cmd_ready = 1'b1;
  assign engine_if_rsp_valid = 1'b0;
  assign engine_if_rsp_result = '0;
  assign engine_if_rsp_status = gf_pkg::STATUS_OK;
  assign engine_if_rsp_txn_id = '0;
  assign engine_if_engine_idle = 1'b1;
  assign mul_req_valid_o = 1'b0;
  assign mul_a_o = '0; assign mul_b_o = '0; assign mul_m_o = '0;
  assign mul_rsp_ready_o = 1'b1;
endmodule

module gf_ecc_engine_wrapper #(
  parameter int unsigned WIDTH = 255, parameter int unsigned CURVE_TYPE = 0
) (
  input  logic clk_i, input logic rst_ni,
  input  logic engine_if_cmd_valid, output logic engine_if_cmd_ready,
  input  logic [3:0] engine_if_cmd_opcode,
  input  logic [7:0] engine_if_cmd_txn_id,
  input  logic [WIDTH-1:0] engine_if_cmd_base, engine_if_cmd_exp, engine_if_cmd_m,
  output logic engine_if_rsp_valid, input logic engine_if_rsp_ready,
  output logic [WIDTH-1:0] engine_if_rsp_result,
  output logic [2:0] engine_if_rsp_status,
  output logic [7:0] engine_if_rsp_txn_id,
  output logic engine_if_engine_idle,
  output logic mul_req_valid_o, input logic mul_req_ready_i,
  output logic [WIDTH-1:0] mul_a_o, mul_b_o, mul_m_o,
  input logic mul_rsp_valid_i, output logic mul_rsp_ready_o,
  input logic [WIDTH-1:0] mul_p_i
);
  assign engine_if_cmd_ready = 1'b1;
  assign engine_if_rsp_valid = 1'b0;
  assign engine_if_rsp_result = '0;
  assign engine_if_rsp_status = gf_pkg::STATUS_OK;
  assign engine_if_rsp_txn_id = '0;
  assign engine_if_engine_idle = 1'b1;
  assign mul_req_valid_o = 1'b0;
  assign mul_a_o = '0; assign mul_b_o = '0; assign mul_m_o = '0;
  assign mul_rsp_ready_o = 1'b1;
endmodule
