// =============================================================================
// gf_transaction_table - In-flight transaction state
// Copyright (c) 2026 Verily. All rights reserved.
//
// One row per operand bank (bank index == table index == txn slot).
// Stores: txn_id, opcode, state, engine_id, operand_bank (implicit = index),
//         completion_pointer (seq), error_flags.
// =============================================================================
`include "gf_pkg.sv"

module gf_transaction_table
  import gf_pkg::*;
(
  input  logic                clk_i,
  input  logic                rst_ni,

  // slot update port (scheduler)
  input  logic                upd_en_i,
  input  logic [SEQ_W-1:0]    upd_slot_i,
  input  gf_txn_state_e       upd_state_i,
  input  logic [TXN_ID_W-1:0] upd_txn_id_i,
  input  gf_opcode_e          upd_opcode_i,
  input  logic [1:0]          upd_engine_id_i,
  input  logic [SEQ_W-1:0]    upd_seq_i,
  input  gf_status_e          upd_status_i,

  // state-only update port (retire path)
  input  logic                ret_en_i,
  input  logic [SEQ_W-1:0]    ret_slot_i,

  // completion port (engine done -> COMPLETE + status)
  input  logic                comp_en_i,
  input  logic [SEQ_W-1:0]    comp_slot_i,
  input  gf_status_e          comp_status_i,

  // read view
  output gf_txn_state_e       state_o      [MAX_TXNS],
  output logic [TXN_ID_W-1:0] txn_id_o     [MAX_TXNS],
  output gf_opcode_e          opcode_o     [MAX_TXNS],
  output logic [SEQ_W-1:0]    seq_o        [MAX_TXNS],
  output gf_status_e          status_o     [MAX_TXNS]
);

  gf_txn_state_e       state_q  [MAX_TXNS];
  logic [TXN_ID_W-1:0] txnid_q  [MAX_TXNS];
  gf_opcode_e          opc_q    [MAX_TXNS];
  logic [1:0]          eng_q    [MAX_TXNS];
  logic [SEQ_W-1:0]    seq_q    [MAX_TXNS];
  gf_status_e          stat_q   [MAX_TXNS];

  assign state_o  = state_q;
  assign txn_id_o = txnid_q;
  assign opcode_o = opc_q;
  assign seq_o    = seq_q;
  assign status_o = stat_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      for (int i = 0; i < MAX_TXNS; i++) begin
        state_q[i] <= TXN_FREE;
        txnid_q[i] <= '0;
        opc_q[i]   <= OP_MODEXP;
        eng_q[i]   <= '0;
        seq_q[i]   <= '0;
        stat_q[i]  <= STATUS_OK;
      end
    end else begin
      if (upd_en_i) begin
        state_q[upd_slot_i] <= upd_state_i;
        txnid_q[upd_slot_i] <= upd_txn_id_i;
        opc_q[upd_slot_i]   <= upd_opcode_i;
        eng_q[upd_slot_i]   <= upd_engine_id_i;
        seq_q[upd_slot_i]   <= upd_seq_i;
        stat_q[upd_slot_i]  <= upd_status_i;
      end
      if (comp_en_i) begin
        state_q[comp_slot_i] <= TXN_COMPLETE;
        stat_q[comp_slot_i]  <= comp_status_i;
      end
      if (ret_en_i) state_q[ret_slot_i] <= TXN_FREE;
    end
  end

endmodule
