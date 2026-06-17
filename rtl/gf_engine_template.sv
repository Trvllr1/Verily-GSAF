// =============================================================================
// gf_engine_template - Starter template for custom GSAF engines
// Copyright (c) 2026 Verily. All rights reserved.
//
// This template implements gf_engine_if.sv and provides a starting point
// for clients to build their own engines. Replace the placeholder logic
// with your custom computation.
//
// The engine must:
//   1. Accept commands via gf_engine_if (cmd_valid/cmd_ready handshaking)
//   2. Process the command (placeholder: simple multiply)
//   3. Return results via gf_engine_if (rsp_valid/rsp_ready handshaking)
//   4. Maintain constant-time behavior (fixed latency, no data branches)
//   5. Report STATUS_FAULT for any internal consistency check failure
//
// See docs/engine-sdk.md for the full developer guide.
// =============================================================================
`include "gf_pkg.sv"

module gf_engine_template
  import gf_pkg::*;
#(
  parameter int unsigned WIDTH = gf_pkg::GF_WIDTH_DEFAULT
) (
  input  logic               clk_i,
  input  logic               rst_ni,

  // command (valid/ready)
  input  logic               valid_i,
  output logic               ready_o,
  input  logic [3:0]         opcode_i,
  input  logic [WIDTH-1:0]   base_i,
  input  logic [WIDTH-1:0]   exp_i,      // unused for most engines
  input  logic [WIDTH-1:0]   m_i,

  // result (valid/ready)
  output logic               valid_o,
  input  logic               ready_i,
  output logic [WIDTH-1:0]   result_o,
  output gf_status_e         status_o,

  output logic               idle_o
);

  // ─── State machine ───────────────────────────────────────────────────────
  typedef enum logic [1:0] {S_IDLE, S_COMPUTE, S_DONE} state_e;
  state_e state_q;

  // ─── Operand registers ──────────────────────────────────────────────────
  logic [WIDTH-1:0] a_q, b_q, m_q;
  logic [WIDTH-1:0] result_q;
  gf_status_e       status_q;

  // ─── Constant-time computation counter ──────────────────────────────────
  // REPLACE THIS with your actual computation latency
  localparam int unsigned COMPUTE_CYCLES = 16;
  localparam int unsigned CNT_W = $clog2(COMPUTE_CYCLES + 1);
  logic [CNT_W-1:0] cnt_q;

  assign ready_o  = (state_q == S_IDLE);
  valid_o  = (state_q == S_DONE);
  assign result_o = result_q;
  assign status_o = status_q;
  assign idle_o   = (state_q == S_IDLE);

  // ─── Main FSM ───────────────────────────────────────────────────────────
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q  <= S_IDLE;
      a_q      <= '0;
      b_q      <= '0;
      m_q      <= '0;
      result_q <= '0;
      status_q <= STATUS_OK;
      cnt_q    <= '0;
    end else begin
      unique case (state_q)
        // ---------------------------------------------------------------
        S_IDLE: begin
          if (valid_i) begin
            a_q      <= base_i;
            b_q      <= exp_i;
            m_q      <= m_i;
            cnt_q    <= '0;
            status_q <= STATUS_OK;
            state_q  <= S_COMPUTE;
          end
        end

        // ---------------------------------------------------------------
        S_COMPUTE: begin
          cnt_q <= cnt_q + 1'b1;

          // =============================================================
          // REPLACE THIS BLOCK with your actual computation
          // Example: simple modular multiply
          // =============================================================
          if (cnt_q == CNT_W'(COMPUTE_CYCLES - 1)) begin
            result_q <= (a_q * b_q) % m_q;  // placeholder!
            state_q  <= S_DONE;
          end
          // =============================================================

          // Fault detection (optional but recommended):
          // if (internal_error) begin
          //   result_q <= '0;
          //   status_q <= STATUS_FAULT;
          //   state_q  <= S_DONE;
          // end
        end

        // ---------------------------------------------------------------
        S_DONE: begin
          if (ready_i) begin
            state_q <= S_IDLE;
            // Secure wipe of operand state
            a_q <= '0;
            b_q <= '0;
          end
        end

        default: state_q <= S_IDLE;
      endcase
    end
  end

  // ─── Constant-time assertion ────────────────────────────────────────────
`ifdef GF_ASSERTIONS
  a_const_time: assert property (@(posedge clk_i) disable iff (!rst_ni)
    (state_q == S_IDLE && valid_i) |-> ##COMPUTE_CYCLES (state_q == S_DONE));
`endif

endmodule
