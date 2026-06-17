// =============================================================================
// gf_scheduler - Dispatch, input screening, and completion collection
// Copyright (c) 2026 Verily. All rights reserved.
//
// Dispatch path (one command per cycle max):
//   command_fifo -> microcode decode -> input screen -> engine handshake
//
// Input screening (STATUS_INVALID_INPUT, no FSM ever deadlocks):
//   - modulus == 0
//   - modulus even
//   - residue operand >= modulus  (exponent operand is exempt: not a residue)
//   Illegal commands complete immediately through the normal completion
//   path so ordering guarantees and one-completion-per-txn still hold.
//
// Completion path (one record per cycle max, engines hold valid until taken):
//   engine -> result write to owned bank -> completion_queue push
//
// NOTE: the completion collector priority mux is a CONTROL-path serializer
// only; it can never alter arithmetic latency of in-flight operations
// (engines' datapaths are fully decoupled and constant-time).
// =============================================================================
`include "gf_pkg.sv"

module gf_scheduler
  import gf_pkg::*;
#(
  parameter int unsigned WIDTH          = gf_pkg::GF_WIDTH_DEFAULT,
  parameter int unsigned EXP_BLIND_BITS = 64,
  localparam int unsigned EXP_W         = WIDTH + EXP_BLIND_BITS
) (
  input  logic                clk_i,
  input  logic                rst_ni,

  // command_fifo pop side
  input  logic                cmd_valid_i,
  output logic                cmd_ready_o,
  input  gf_cmd_t             cmd_i,

  // operand bank read port (dispatch-cycle read, statically owned bank)
  output logic [SEQ_W-1:0]    bank_rd_o,
  input  logic [WIDTH-1:0]    bank_a_i,
  input  logic [EXP_W-1:0]    bank_b_i,
  input  logic [WIDTH-1:0]    bank_m_i,

  // engine 0: modexp
  output logic                e0_valid_o,
  input  logic                e0_ready_i,
  output logic [WIDTH-1:0]    e0_base_o,
  output logic [EXP_W-1:0]    e0_exp_o,
  output logic [WIDTH-1:0]    e0_m_o,
  input  logic                e0_done_valid_i,
  output logic                e0_done_ready_o,
  input  logic [WIDTH-1:0]    e0_result_i,
  input  gf_status_e          e0_status_i,

  // engine 1: modinv
  output logic                e1_valid_o,
  input  logic                e1_ready_i,
  output logic [WIDTH-1:0]    e1_a_o,
  output logic [WIDTH-1:0]    e1_m_o,
  input  logic                e1_done_valid_i,
  output logic                e1_done_ready_o,
  input  logic [WIDTH-1:0]    e1_result_i,
  input  gf_status_e          e1_status_i,

  // result write-back to owned bank
  output logic                res_we_o,
  output logic [SEQ_W-1:0]    res_bank_o,
  output logic [WIDTH-1:0]    res_data_o,

  // completion_queue push side
  output logic                cq_valid_o,
  input  logic                cq_ready_i,
  output gf_completion_t      cq_data_o,

  // transaction table
  output logic                tt_upd_en_o,
  output logic [SEQ_W-1:0]    tt_upd_slot_o,
  output gf_txn_state_e       tt_upd_state_o,
  output logic [TXN_ID_W-1:0] tt_upd_txn_id_o,
  output gf_opcode_e          tt_upd_opcode_o,
  output logic [1:0]          tt_upd_engine_id_o,
  output logic [SEQ_W-1:0]    tt_upd_seq_o,
  output gf_status_e          tt_upd_status_o,
  output logic                tt_comp_en_o,
  output logic [SEQ_W-1:0]    tt_comp_slot_o,
  output gf_status_e          tt_comp_status_o,
  input  gf_txn_state_e       tt_state_i [MAX_TXNS],

  // status
  output logic [MAX_TXNS-1:0] bank_free_o,
  output logic                busy_o
);

  // ---------------------------------------------------------------------------
  // microcode decode
  // ---------------------------------------------------------------------------
  logic       uc_legal;
  logic [1:0] uc_class;
  gf_microcode_rom u_ucode (
    .opcode_i       (cmd_i.opcode),
    .legal_o        (uc_legal),
    .engine_class_o (uc_class)
  );

  // ---------------------------------------------------------------------------
  // dispatch-cycle input screen (combinational on bank read)
  // ---------------------------------------------------------------------------
  assign bank_rd_o = cmd_i.bank;

  logic m_bad, a_bad, screen_fail;
  assign m_bad = (bank_m_i == '0) || !bank_m_i[0];
  assign a_bad = (bank_a_i >= bank_m_i);
  assign screen_fail = m_bad || a_bad;   // exponent (B) exempt from range check

  gf_status_e dispatch_status;
  always_comb begin
    if (!uc_legal)        dispatch_status = STATUS_UNSUPPORTED;
    else if (screen_fail) dispatch_status = STATUS_INVALID_INPUT;
    else                  dispatch_status = STATUS_OK;
  end

  logic dispatch_err;
  assign dispatch_err = (dispatch_status != STATUS_OK);

  // target engine availability
  logic engine_ready;
  assign engine_ready = (uc_class == 2'd0) ? e0_ready_i : e1_ready_i;

  // ---------------------------------------------------------------------------
  // error-completion holding register (drains via completion arbiter)
  // ---------------------------------------------------------------------------
  logic           err_pend_q;
  gf_completion_t err_rec_q;

  // pop a command when we can fully act on it this cycle
  assign cmd_ready_o = dispatch_err ? !err_pend_q : engine_ready;
  wire   cmd_fire    = cmd_valid_i && cmd_ready_o;
  wire   dispatch_ok = cmd_fire && !dispatch_err;

  // sequence counter: dispatch order == acceptance order (FIFO preserves it)
  logic [SEQ_W-1:0] seq_ctr_q;

  // engine occupancy bookkeeping
  logic             eng_busy_q [2];
  logic [SEQ_W-1:0] eng_slot_q [2];
  logic [SEQ_W-1:0] eng_seq_q  [2];
  logic [TXN_ID_W-1:0] eng_txn_q [2];
  gf_opcode_e       eng_opc_q  [2];

  // engine command drive (operands straight from owned bank, latched by engine)
  assign e0_valid_o = dispatch_ok && (uc_class == 2'd0);
  assign e0_base_o  = bank_a_i;
  assign e0_exp_o   = bank_b_i;
  assign e0_m_o     = bank_m_i;

  assign e1_valid_o = dispatch_ok && (uc_class == 2'd1);
  assign e1_a_o     = bank_a_i;
  assign e1_m_o     = bank_m_i;

  // ---------------------------------------------------------------------------
  // completion collector: fixed-priority serializer (control path only)
  //   err_pending > engine0 > engine1 ; source holds until CQ accepts
  // ---------------------------------------------------------------------------
  logic grant_err, grant_e0, grant_e1;
  assign grant_err = err_pend_q;
  assign grant_e0  = !grant_err && e0_done_valid_i;
  assign grant_e1  = !grant_err && !grant_e0 && e1_done_valid_i;

  assign cq_valid_o = grant_err || grant_e0 || grant_e1;

  always_comb begin
    cq_data_o = '0;
    if (grant_err) begin
      cq_data_o = err_rec_q;
    end else if (grant_e0) begin
      cq_data_o = '{txn_id: eng_txn_q[0], opcode: eng_opc_q[0],
                    status: e0_status_i, bank: eng_slot_q[0], seq: eng_seq_q[0]};
    end else if (grant_e1) begin
      cq_data_o = '{txn_id: eng_txn_q[1], opcode: eng_opc_q[1],
                    status: e1_status_i, bank: eng_slot_q[1], seq: eng_seq_q[1]};
    end
  end

  wire cq_fire = cq_valid_o && cq_ready_i;

  assign e0_done_ready_o = grant_e0 && cq_ready_i;
  assign e1_done_ready_o = grant_e1 && cq_ready_i;

  // result write-back accompanies the granted engine completion
  assign res_we_o   = cq_fire && (grant_e0 || grant_e1);
  assign res_bank_o = grant_e0 ? eng_slot_q[0] : eng_slot_q[1];
  assign res_data_o = grant_e0 ? e0_result_i   : e1_result_i;

  // ---------------------------------------------------------------------------
  // transaction table writes
  // ---------------------------------------------------------------------------
  assign tt_upd_en_o        = cmd_fire;
  assign tt_upd_slot_o      = cmd_i.bank;
  assign tt_upd_state_o     = dispatch_err ? TXN_COMPLETE : TXN_RUNNING;
  assign tt_upd_txn_id_o    = cmd_i.txn_id;
  assign tt_upd_opcode_o    = cmd_i.opcode;
  assign tt_upd_engine_id_o = uc_class;
  assign tt_upd_seq_o       = seq_ctr_q;
  assign tt_upd_status_o    = dispatch_status;

  assign tt_comp_en_o     = cq_fire && (grant_e0 || grant_e1);
  assign tt_comp_slot_o   = res_bank_o;
  assign tt_comp_status_o = grant_e0 ? e0_status_i : e1_status_i;

  // ---------------------------------------------------------------------------
  // free-bank view + busy
  // ---------------------------------------------------------------------------
  always_comb begin
    for (int i = 0; i < MAX_TXNS; i++)
      bank_free_o[i] = (tt_state_i[i] == TXN_FREE);
  end
  assign busy_o = eng_busy_q[0] || eng_busy_q[1] || err_pend_q || cmd_valid_i;

  // ---------------------------------------------------------------------------
  // sequential state
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      seq_ctr_q  <= '0;
      err_pend_q <= 1'b0;
      err_rec_q  <= '0;
      for (int k = 0; k < 2; k++) begin
        eng_busy_q[k] <= 1'b0;
        eng_slot_q[k] <= '0;
        eng_seq_q[k]  <= '0;
        eng_txn_q[k]  <= '0;
        eng_opc_q[k]  <= OP_MODEXP;
      end
    end else begin
      if (cmd_fire) begin
        seq_ctr_q <= seq_ctr_q + 1'b1;
        if (dispatch_err) begin
          err_pend_q <= 1'b1;
          err_rec_q  <= '{txn_id: cmd_i.txn_id, opcode: cmd_i.opcode,
                          status: dispatch_status, bank: cmd_i.bank,
                          seq: seq_ctr_q};
        end else begin
          eng_busy_q[uc_class[0]] <= 1'b1;
          eng_slot_q[uc_class[0]] <= cmd_i.bank;
          eng_seq_q[uc_class[0]]  <= seq_ctr_q;
          eng_txn_q[uc_class[0]]  <= cmd_i.txn_id;
          eng_opc_q[uc_class[0]]  <= cmd_i.opcode;
        end
      end
      if (cq_fire) begin
        if (grant_err) err_pend_q <= 1'b0;
        if (grant_e0)  eng_busy_q[0] <= 1'b0;
        if (grant_e1)  eng_busy_q[1] <= 1'b0;
      end
    end
  end

`ifdef GF_ASSERTIONS
  // no duplicate dispatch onto a busy engine
  a_e0_excl: assert property (@(posedge clk_i) disable iff (!rst_ni)
    e0_valid_o |-> e0_ready_i);
  a_e1_excl: assert property (@(posedge clk_i) disable iff (!rst_ni)
    e1_valid_o |-> e1_ready_i);
`endif

endmodule
