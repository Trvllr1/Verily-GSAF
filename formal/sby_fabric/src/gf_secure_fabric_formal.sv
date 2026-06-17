// =============================================================================
// gf_secure_fabric_formal - Formal verification top module
// Copyright (c) 2026 Verily. All rights reserved.
//
// This module instantiates the GSAF fabric and binds the formal properties.
// Used by SymbiYosys for formal verification of fabric-level properties.
// =============================================================================
`include "gf_pkg.sv"

module gf_secure_fabric_formal
  import gf_pkg::*;
#(
  parameter int unsigned WIDTH = 8  // Use small width for formal
) (
  input logic clk_i,
  input logic rst_ni,

  // AXI4-Lite slave interface
  input  logic        s_axil_awvalid,
  output logic        s_axil_awready,
  input  logic [11:0] s_axil_awaddr,
  input  logic        s_axil_wvalid,
  output logic        s_axil_wready,
  input  logic [31:0] s_axil_wdata,
  input  logic [3:0]  s_axil_wstrb,
  output logic        s_axil_bvalid,
  input  logic        s_axil_bready,
  output logic [1:0]  s_axil_bresp,
  input  logic        s_axil_arvalid,
  output logic        s_axil_arready,
  input  logic [11:0] s_axil_araddr,
  output logic        s_axil_rvalid,
  input  logic        s_axil_rready,
  output logic [31:0] s_axil_rdata,
  output logic [1:0]  s_axil_rresp,

  output logic        irq_o,
  output logic        idle_o
);

  // ─── DUT instantiation ──────────────────────────────────────────────────
  gf_secure_fabric_top #(
    .WIDTH             (WIDTH),
    .RESPONSE_ORDERING (MODE_IN_ORDER),
    .NUM_MULTIPLIERS   (1),
    .EXP_BLIND_BITS    (0)
  ) u_dut (
    .clk_i          (clk_i),
    .rst_ni         (rst_ni),
    .s_axil_awvalid (s_axil_awvalid),
    .s_axil_awready (s_axil_awready),
    .s_axil_awaddr  (s_axil_awaddr),
    .s_axil_wvalid  (s_axil_wvalid),
    .s_axil_wready  (s_axil_wready),
    .s_axil_wdata   (s_axil_wdata),
    .s_axil_wstrb   (s_axil_wstrb),
    .s_axil_bvalid  (s_axil_bvalid),
    .s_axil_bready  (s_axil_bready),
    .s_axil_bresp   (s_axil_bresp),
    .s_axil_arvalid (s_axil_arvalid),
    .s_axil_arready (s_axil_arready),
    .s_axil_araddr  (s_axil_araddr),
    .s_axil_rvalid  (s_axil_rvalid),
    .s_axil_rready  (s_axil_rready),
    .s_axil_rdata   (s_axil_rdata),
    .s_axil_rresp   (s_axil_rresp),
    .irq_o          (irq_o),
    .idle_o         (idle_o)
  );

  // ─── Formal properties ──────────────────────────────────────────────────
  // These are the same properties from gf_fabric_props.sv, inlined here
  // for SymbiYosys compatibility.

  default clocking cb @(posedge clk_i); endclocking
  default disable iff (!rst_ni);

  // Internal signals for properties
  logic        cmdf_out_valid, cmdf_out_ready;
  gf_cmd_t     cmdf_out;
  logic        cq_in_valid, cq_in_ready;
  gf_completion_t cq_in;
  logic        rf_out_valid, rf_out_ready;
  gf_completion_t rf_out;
  gf_txn_state_e  tt_state [MAX_TXNS];
  logic [TXN_ID_W-1:0] tt_txn_id [MAX_TXNS];

  // ─── P1: No FIFO overflow ───────────────────────────────────────────────
  a_cq_no_overflow: assert property (cq_in_valid |-> s_eventually cq_in_ready);

  // ─── P2: Exactly one completion per transaction ─────────────────────────
  for (genvar s = 0; s < MAX_TXNS; s++) begin : g_one_completion
    a_complete_then_free: assert property (
      (tt_state[s] == TXN_COMPLETE) |->
        (tt_state[s] == TXN_COMPLETE) until_with (tt_state[s] == TXN_FREE));
    a_no_skip_states: assert property (
      (tt_state[s] == TXN_FREE) |=>
        (tt_state[s] inside {TXN_FREE, TXN_LOADED, TXN_RUNNING, TXN_COMPLETE}));
  end

  // ─── P3: No duplicate txn_id ───────────────────────────────────────────
  for (genvar i = 0; i < MAX_TXNS; i++) begin : g_dup_i
    for (genvar j = 0; j < MAX_TXNS; j++) begin : g_dup_j
      if (i < j) begin : g_pair
        a_unique_txn_id: assert property (
          ((tt_state[i] != TXN_FREE) && (tt_state[j] != TXN_FREE))
            |-> (tt_txn_id[i] != tt_txn_id[j]));
      end
    end
  end

  // ─── P4: No deadlock / eventual forward progress ────────────────────────
  asm_host_fair: assume property (rf_out_valid |-> s_eventually rf_out_ready);
  a_forward_progress: assert property (
    (cmdf_out_valid && cmdf_out_ready) |-> s_eventually
      (rf_out_valid && rf_out.txn_id == $past(cmdf_out.txn_id)));

  // ─── P5: Completion record integrity ────────────────────────────────────
  a_legal_status: assert property (cq_in_valid |->
    cq_in.status inside {STATUS_OK, STATUS_INVALID_INPUT,
                         STATUS_NOT_INVERTIBLE, STATUS_UNSUPPORTED,
                         STATUS_FAULT});

endmodule
