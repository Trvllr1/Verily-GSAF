// =============================================================================
// gf_modinv_engine_wrapper - Adapts gf_modinv_engine to gf_engine_if
// Copyright (c) 2026 Verily. All rights reserved.
//
// This wrapper connects the existing gf_modinv_engine ports to the formally
// specified gf_engine_if interface. The engine itself is NOT modified.
//
// ModInv does not use the multiplier lane (it uses Bernstein-Yang divsteps),
// so the multiplier signals are unconnected.
// =============================================================================
`include "gf_pkg.sv"

module gf_modinv_engine_wrapper
  import gf_pkg::*;
#(
  parameter int unsigned WIDTH         = gf_pkg::GF_WIDTH_DEFAULT,
  parameter int unsigned DIVSTEP_BOUND = gf_pkg::GF_DIVSTEP_BOUND_64  // Use pre-computed value
) (
  input  logic clk_i,
  input  logic rst_ni,

  // Engine interface (chassis side)
  gf_engine_if.chassis_mp engine_if
);

  // ─── Engine instantiation ────────────────────────────────────────────────
  gf_modinv_engine #(
    .WIDTH         (WIDTH),
    .DIVSTEP_BOUND (DIVSTEP_BOUND)
  ) u_engine (
    .clk_i    (clk_i),
    .rst_ni   (rst_ni),
    // command
    .valid_i  (engine_if.cmd_valid),
    .ready_o  (engine_if.cmd_ready),
    .a_i      (engine_if.cmd_base),   // a maps to cmd_base
    .m_i      (engine_if.cmd_m),
    // result
    .valid_o  (engine_if.rsp_valid),
    .ready_i  (engine_if.rsp_ready),
    .result_o (engine_if.rsp_result),
    .status_o (engine_if.rsp_status),
    // status
    .idle_o   (engine_if.engine_idle)
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
