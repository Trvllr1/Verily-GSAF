// =============================================================================
// gf_reorder_buffer - Optional in-order response restoration
// Copyright (c) 2026 Verily. All rights reserved.
//
// RESPONSE_ORDERING = MODE_OOO      : pure passthrough (zero added latency)
// RESPONSE_ORDERING = MODE_IN_ORDER : completions parked by seq tag; emitted
//                                     strictly in original acceptance order.
//
// Capacity = MAX_TXNS, one slot per seq value; with <= MAX_TXNS in flight the
// seq tag is unique among parked entries, so wraparound is safe (UVM coverage
// item 7 exercises the wrap).
// =============================================================================
`include "gf_pkg.sv"

module gf_reorder_buffer
  import gf_pkg::*;
#(
  parameter gf_order_mode_e RESPONSE_ORDERING = MODE_OOO
) (
  input  logic           clk_i,
  input  logic           rst_ni,

  input  logic           valid_i,
  output logic           ready_o,
  input  gf_completion_t data_i,

  output logic           valid_o,
  input  logic           ready_i,
  output gf_completion_t data_o
);

  if (RESPONSE_ORDERING == MODE_OOO) begin : g_passthrough

    assign valid_o = valid_i;
    assign ready_o = ready_i;
    assign data_o  = data_i;

  end else begin : g_inorder

    gf_completion_t slot_q  [MAX_TXNS];
    logic           svalid_q[MAX_TXNS];
    logic [SEQ_W-1:0] expect_q;

    // head-of-order entry available?
    wire head_parked = svalid_q[expect_q];
    wire head_incoming = valid_i && (data_i.seq == expect_q);

    assign valid_o = head_parked || head_incoming;
    assign data_o  = head_parked ? slot_q[expect_q] : data_i;
    // accept incoming if it's the head being consumed, or parkable
    assign ready_o = head_incoming ? (head_parked ? 1'b0 : ready_i || !svalid_q[data_i.seq])
                                   : !svalid_q[data_i.seq];

    wire out_fire = valid_o && ready_i;
    wire in_fire  = valid_i && ready_o;
    wire in_is_emitted = in_fire && head_incoming && !head_parked && ready_i;

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        expect_q <= '0;
        for (int i = 0; i < MAX_TXNS; i++) begin
          svalid_q[i] <= 1'b0;
          slot_q[i]   <= '0;
        end
      end else begin
        if (in_fire && !in_is_emitted) begin
          slot_q[data_i.seq]   <= data_i;
          svalid_q[data_i.seq] <= 1'b1;
        end
        if (out_fire) begin
          if (head_parked) svalid_q[expect_q] <= 1'b0;
          expect_q <= expect_q + 1'b1;   // natural wraparound, SEQ_W bits
        end
      end
    end

`ifdef GF_ASSERTIONS
    // never park onto an occupied slot (seq uniqueness among in-flight txns)
    a_no_slot_clobber: assert property (@(posedge clk_i) disable iff (!rst_ni)
      (valid_i && ready_o && !(head_incoming && !head_parked && ready_i))
        |-> !svalid_q[data_i.seq]);
`endif

  end

endmodule
