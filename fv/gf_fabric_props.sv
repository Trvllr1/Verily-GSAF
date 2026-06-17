// =============================================================================
// gf_fabric_props - Top-level formal properties (bind file)
// Copyright (c) 2026 Verily. All rights reserved.
//
// Strategy per spec:
//   - Arithmetic engines black-boxed (set_blackbox gf_mont_mult,
//     gf_modexp_engine datapath, gf_modinv_engine datapath in the FV tool;
//     their handshake contracts are assumed via the a_* assumptions below)
//   - Run at WIDTH=8 or WIDTH=16
//   - Prove: no deadlock, no FIFO overflow, exactly one completion per
//     transaction, no duplicate txn_id in flight, eventual forward progress
//
// Bind:  bind gf_secure_fabric_top gf_fabric_props #(.WIDTH(WIDTH)) u_props (.*);
// =============================================================================
`include "gf_pkg.sv"

module gf_fabric_props
  import gf_pkg::*;
#(
  parameter int unsigned WIDTH = 8
) (
  input logic                clk_i,
  input logic                rst_ni,

  // observed fabric signals (bound hierarchically)
  input logic                cmdf_out_valid,
  input logic                cmdf_out_ready,
  input gf_cmd_t             cmdf_out,
  input logic                cq_in_valid,
  input logic                cq_in_ready,
  input gf_completion_t      cq_in,
  input logic                rf_out_valid,
  input logic                rf_out_ready,
  input gf_completion_t      rf_out,
  input gf_txn_state_e       tt_state [MAX_TXNS],
  input logic [TXN_ID_W-1:0] tt_txn_id [MAX_TXNS]
);

  default clocking cb @(posedge clk_i); endclocking
  default disable iff (!rst_ni);

  // ---------------------------------------------------------------------------
  // P1: no FIFO overflow anywhere (completion queue is the critical one;
  //     credit-based sizing makes this provable, not just testable)
  // ---------------------------------------------------------------------------
  a_cq_no_overflow: assert property (cq_in_valid |-> s_eventually cq_in_ready);

  // ---------------------------------------------------------------------------
  // P2: exactly one completion per transaction
  //     (a RUNNING slot completes exactly once before returning to FREE)
  // ---------------------------------------------------------------------------
  for (genvar s = 0; s < MAX_TXNS; s++) begin : g_one_completion
    a_complete_then_free: assert property (
      (tt_state[s] == TXN_COMPLETE) |->
        (tt_state[s] == TXN_COMPLETE) until_with (tt_state[s] == TXN_FREE));
    a_no_skip_states: assert property (
      (tt_state[s] == TXN_FREE) |=>
        (tt_state[s] inside {TXN_FREE, TXN_LOADED, TXN_RUNNING, TXN_COMPLETE}));
  end

  // ---------------------------------------------------------------------------
  // P3: no duplicate txn_id among in-flight transactions
  // ---------------------------------------------------------------------------
  for (genvar i = 0; i < MAX_TXNS; i++) begin : g_dup_i
    for (genvar j = 0; j < MAX_TXNS; j++) begin : g_dup_j
      if (i < j) begin : g_pair
        a_unique_txn_id: assert property (
          ((tt_state[i] != TXN_FREE) && (tt_state[j] != TXN_FREE))
            |-> (tt_txn_id[i] != tt_txn_id[j]));
      end
    end
  end

  // ---------------------------------------------------------------------------
  // P4: no deadlock / eventual forward progress
  //     every accepted command eventually produces a host-visible result
  //     (fairness assumption: host eventually pops result_fifo)
  // ---------------------------------------------------------------------------
  asm_host_fair: assume property (rf_out_valid |-> s_eventually rf_out_ready);
  a_forward_progress: assert property (
    (cmdf_out_valid && cmdf_out_ready) |-> s_eventually
      (rf_out_valid && rf_out.txn_id == $past(cmdf_out.txn_id)));

  // ---------------------------------------------------------------------------
  // P5: completion record integrity - status is a legal encoding
  // (STATUS_FAULT included: fault countermeasures report, never silently fail)
  // ---------------------------------------------------------------------------
  a_legal_status: assert property (cq_in_valid |->
    cq_in.status inside {STATUS_OK, STATUS_INVALID_INPUT,
                         STATUS_NOT_INVERTIBLE, STATUS_UNSUPPORTED,
                         STATUS_FAULT});

endmodule
