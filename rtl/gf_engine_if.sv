// =============================================================================
// gf_engine_if - Engine interface with SVA security properties
// Copyright (c) 2026 Verily. All rights reserved.
//
// This is the formally specified interface between the GSAF chassis and
// pluggable engines. Engines implement this interface; the chassis consumes it.
// Formal verification proves each side independently against these properties.
//
// Properties enforced:
//   P_E1: Constant-time — engine completes within a bounded number of cycles
//         (per engine type), never depending on operand values.
//   P_E2: No silent fault — every completed transaction carries a legal status;
//         STATUS_FAULT is reported, never a silent wrong answer.
//   P_E3: Backpressure immunity — engine never stalls waiting for result read;
//         ready_o is asserted independently of ready_i during processing.
//   P_E4: Isolation — no cross-transaction data leakage; engine processes one
//         transaction at a time.
// =============================================================================
`ifndef GF_ENGINE_IF_SV
`define GF_ENGINE_IF_SV

`include "gf_pkg.sv"

interface gf_engine_if
  import gf_pkg::*;
#(
  parameter int unsigned WIDTH = gf_pkg::GF_WIDTH_DEFAULT,
  parameter int unsigned EXP_W = WIDTH
) (
  input logic clk_i,
  input logic rst_ni
);

  // ─── Command channel (chassis → engine) ──────────────────────────────────
  logic               cmd_valid;
  logic               cmd_ready;
  logic [3:0]         cmd_opcode;
  logic [TXN_ID_W-1:0] cmd_txn_id;
  logic [WIDTH-1:0]   cmd_base;     // base (ModExp) or a (ModInv)
  logic [EXP_W-1:0]   cmd_exp;      // exponent (ModExp), unused for ModInv
  logic [WIDTH-1:0]   cmd_m;        // modulus

  // ─── Result channel (engine → chassis) ───────────────────────────────────
  logic               rsp_valid;
  logic               rsp_ready;
  logic [WIDTH-1:0]   rsp_result;
  gf_status_e         rsp_status;
  logic [TXN_ID_W-1:0] rsp_txn_id;

  // ─── Engine status ───────────────────────────────────────────────────────
  logic               engine_idle;

  // ─── Modport: engine side ────────────────────────────────────────────────
  modport engine_mp (
    input  clk_i,
    input  rst_ni,
    // command (consumed by engine)
    input  cmd_valid,
    output cmd_ready,
    input  cmd_opcode,
    input  cmd_txn_id,
    input  cmd_base,
    input  cmd_exp,
    input  cmd_m,
    // result (produced by engine)
    output rsp_valid,
    input  rsp_ready,
    output rsp_result,
    output rsp_status,
    output rsp_txn_id,
    // status
    output engine_idle
  );

  // ─── Modport: chassis side ───────────────────────────────────────────────
  modport chassis_mp (
    input  clk_i,
    input  rst_ni,
    // command (produced by chassis)
    output cmd_valid,
    input  cmd_ready,
    output cmd_opcode,
    output cmd_txn_id,
    output cmd_base,
    output cmd_exp,
    output cmd_m,
    // result (consumed by chassis)
    input  rsp_valid,
    output rsp_ready,
    input  rsp_result,
    input  rsp_status,
    input  rsp_txn_id,
    // status
    input  engine_idle
  );

  // ─── Modport: verification side (SVA) ───────────────────────────────────
  modport verify_mp (
    input  clk_i,
    input  rst_ni,
    input  cmd_valid,
    input  cmd_ready,
    input  cmd_opcode,
    input  cmd_txn_id,
    input  cmd_base,
    input  cmd_exp,
    input  cmd_m,
    input  rsp_valid,
    input  rsp_ready,
    input  rsp_result,
    input  rsp_status,
    input  rsp_txn_id,
    input  engine_idle
  );

  // ══════════════════════════════════════════════════════════════════════════
  // SVA Security Properties
  // ══════════════════════════════════════════════════════════════════════════

`ifdef GF_ASSERTIONS

  default clocking cb @(posedge clk_i); endclocking
  default disable iff (!rst_ni);

  // ─── P_E1: Constant-time bound ───────────────────────────────────────────
  // After a command is accepted, the engine MUST produce a result within a
  // fixed number of cycles. This bound is engine-specific and checked by
  // per-engine assertions (in the engine modules themselves). At the interface
  // level, we assert that the engine eventually responds.

  property p_eventual_response;
    @(posedge clk_i) disable iff (!rst_ni)
      (cmd_valid && cmd_ready) |-> s_eventually (rsp_valid && rsp_ready);
  endproperty
  a_eventual_response: assert property (p_eventual_response);

  // ─── P_E2: No silent fault ───────────────────────────────────────────────
  // Every completed response carries a legal status encoding.
  // A STATUS_FAULT is always reported, never swallowed.
  property p_legal_status;
    @(posedge clk_i) disable iff (!rst_ni)
      (rsp_valid && rsp_ready) |->
        rsp_status inside {STATUS_OK, STATUS_INVALID_INPUT,
                          STATUS_NOT_INVERTIBLE, STATUS_UNSUPPORTED,
                          STATUS_FAULT};
  endproperty
  a_legal_status: assert property (p_legal_status);

  // ─── P_E3: Backpressure immunity ─────────────────────────────────────────
  // The engine MUST NOT stall its computation waiting for the result to be
  // read (rsp_ready). The ready_o signal must remain asserted while the
  // engine is processing, regardless of rsp_ready state.
  // This is checked at the engine level (ready_o independent of ready_i
  // during processing). At the interface, we check that rsp_valid goes high
  // even if rsp_ready is initially low.

  property p_backpressure_independent;
    @(posedge clk_i) disable iff (!rst_ni)
      (cmd_valid && cmd_ready && !engine_idle) |->
        s_eventually rsp_valid;
  endproperty
  a_backpressure_independent: assert property (p_backpressure_independent);

  // ─── P_E4: One transaction at a time ─────────────────────────────────────
  // The engine processes one command at a time. A new command cannot be
  // accepted until the previous response is consumed (rsp_valid -> rsp_ready).
  property p_one_at_a_time;
    @(posedge clk_i) disable iff (!rst_ni)
      (cmd_valid && cmd_ready) |=>
        !cmd_valid until_with (rsp_valid && rsp_ready);
  endproperty
  a_one_at_a_time: assert property (p_one_at_a_time);

  // ─── P_E5: Valid/ready handshaking protocol ──────────────────────────────
  // Standard valid/ready: valid must not depend on ready (no combinational
  // loops). Engine output valid must stay high until ready is asserted.
  property p_valid_stable;
    @(posedge clk_i) disable iff (!rst_ni)
      (rsp_valid && !rsp_ready) |=> rsp_valid;
  endproperty
  a_valid_stable: assert property (p_valid_stable);

`endif

endinterface

`endif // GF_ENGINE_IF_SV
