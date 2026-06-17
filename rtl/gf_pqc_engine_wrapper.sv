// =============================================================================
// gf_pqc_engine_wrapper - Adapts gf_pqc_engine to gf_engine_if
// Copyright (c) 2026 Verily. All rights reserved.
//
// This wrapper connects the existing gf_pqc_engine ports to the formally
// specified gf_engine_if interface. The engine itself is NOT modified.
// =============================================================================
`include "gf_pkg.sv"

module gf_pqc_engine_wrapper
  import gf_pkg::*;
#(
  parameter int unsigned WIDTH = 23,   // log2(q) for ML-DSA
  parameter int unsigned N     = 256,
  parameter int unsigned Q     = 8380417
) (
  input  logic clk_i,
  input  logic rst_ni,

  // Engine interface (chassis side)
  gf_engine_if.engine_mp engine_if,

  // Reserved multiplier lane (pass-through to cluster)
  output logic               mul_req_valid_o,
  input  logic               mul_req_ready_i,
  output logic [WIDTH-1:0]   mul_a_o,
  output logic [WIDTH-1:0]   mul_b_o,
  output logic [WIDTH-1:0]   mul_m_o,
  input  logic               mul_rsp_valid_i,
  output logic               mul_rsp_ready_o,
  input  logic [WIDTH-1:0]   mul_p_i,

  // Coefficient memory interface
  output logic               coeff_wr_en,
  output logic [$clog2(N)-1:0] coeff_wr_addr,
  output logic [WIDTH-1:0]   coeff_wr_data,
  output logic               coeff_rd_en,
  output logic [$clog2(N)-1:0] coeff_rd_addr,
  input  logic [WIDTH-1:0]   coeff_rd_data
);

  // ─── Engine instantiation ────────────────────────────────────────────────
  gf_pqc_engine #(
    .WIDTH (WIDTH),
    .N     (N),
    .Q     (Q)
  ) u_engine (
    .clk_i          (clk_i),
    .rst_ni         (rst_ni),
    // command
    .valid_i        (engine_if.cmd_valid),
    .ready_o        (engine_if.cmd_ready),
    .opcode_i       (engine_if.cmd_opcode),
    .base_i         (engine_if.cmd_base),
    .m_i            (engine_if.cmd_m),
    // result
    .valid_o        (engine_if.rsp_valid),
    .ready_i        (engine_if.rsp_ready),
    .result_o       (engine_if.rsp_result),
    .status_o       (engine_if.rsp_status),
    // multiplier lane
    .mul_req_valid_o(mul_req_valid_o),
    .mul_req_ready_i(mul_req_ready_i),
    .mul_a_o        (mul_a_o),
    .mul_b_o        (mul_b_o),
    .mul_m_o        (mul_m_o),
    .mul_rsp_valid_i(mul_rsp_valid_i),
    .mul_rsp_ready_o(mul_rsp_ready_o),
    .mul_p_i        (mul_p_i),
    // status
    .idle_o         (engine_if.engine_idle),
    // coefficient memory
    .coeff_wr_en    (coeff_wr_en),
    .coeff_wr_addr  (coeff_wr_addr),
    .coeff_wr_data  (coeff_wr_data),
    .coeff_rd_en    (coeff_rd_en),
    .coeff_rd_addr  (coeff_rd_addr),
    .coeff_rd_data  (coeff_rd_data)
  );

  // ─── Txn ID passthrough ──────────────────────────────────────────────────
  logic [TXN_ID_W-1:0] txn_id_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      txn_id_q <= '0;
    end else begin
      if (engine_if.cmd_valid && engine_if.cmd_ready)
        txn_id_q <= engine_if.cmd_txn_id;
    end
  end

  assign engine_if.rsp_txn_id = txn_id_q;

endmodule
