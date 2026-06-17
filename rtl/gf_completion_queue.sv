// =============================================================================
// gf_completion_queue - Credit-based completion record queue
// Copyright (c) 2026 Verily. All rights reserved.
//
// Stores {txn_id, opcode, status, result pointer (bank), seq}.
//
// OVERFLOW IS IMPOSSIBLE BY CONSTRUCTION (design improvement over draft spec,
// which listed "completion queue overflow" as a coverage item): depth equals
// MAX_TXNS and at most MAX_TXNS transactions are in flight, each producing
// exactly one completion. The SVA below turns this into a proof obligation
// instead of a test hope.
// =============================================================================
`include "gf_pkg.sv"

module gf_completion_queue
  import gf_pkg::*;
(
  input  logic           clk_i,
  input  logic           rst_ni,

  input  logic           valid_i,
  output logic           ready_o,
  input  gf_completion_t data_i,

  output logic           valid_o,
  input  logic           ready_i,
  output gf_completion_t data_o,

  output logic [$clog2(MAX_TXNS+1)-1:0] count_o
);

  gf_fifo #(
    .DATA_W ($bits(gf_completion_t)),
    .DEPTH  (MAX_TXNS)
  ) u_fifo (
    .clk_i,
    .rst_ni,
    .valid_i,
    .ready_o,
    .data_i,
    .valid_o,
    .ready_i,
    .data_o,
    .count_o
  );

`ifdef GF_ASSERTIONS
  // overflow designed out: a push is always accepted
  a_never_full_on_push: assert property (@(posedge clk_i) disable iff (!rst_ni)
    valid_i |-> ready_o);
`endif

endmodule
