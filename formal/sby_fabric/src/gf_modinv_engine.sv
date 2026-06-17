// =============================================================================
// gf_modinv_engine - Constant-time modular inverse (Bernstein-Yang divsteps)
// Copyright (c) 2026 Verily. All rights reserved.
//
// result = a^-1 mod m  (m odd). Detects non-invertible inputs (gcd != 1).
//
// Registers per spec: delta, f, g, v, r.
// Iteration count: DIVSTEP_BOUND, the *published machine-checked bound*
//   d <  46 : floor((49d + 80)/17)
//   d >= 46 : floor((49d + 57)/17)
// (Bernstein-Yang 2019, "Fast constant-time gcd computation and modular
// inversion"). NOT 2*WIDTH. See gf_pkg::gf_divstep_bound.
//
// CONSTANT-TIME CONTRACT: exactly DIVSTEP_BOUND iterations for all inputs;
// each iteration computes both branch outcomes and muxes (no data branches).
// Algorithm mirrors model/golden_model.py::modinv_divsteps exactly.
// =============================================================================
`include "gf_pkg.sv"

module gf_modinv_engine
  import gf_pkg::*;
#(
  parameter int unsigned WIDTH         = gf_pkg::GF_WIDTH_DEFAULT,
  parameter int unsigned DIVSTEP_BOUND = gf_pkg::GF_DIVSTEP_BOUND_64  // Use pre-computed value
) (
  input  logic               clk_i,
  input  logic               rst_ni,

  // command (valid/ready)
  input  logic               valid_i,
  output logic               ready_o,
  input  logic [WIDTH-1:0]   a_i,
  input  logic [WIDTH-1:0]   m_i,

  // result (valid/ready)
  output logic               valid_o,
  input  logic               ready_i,
  output logic [WIDTH-1:0]   result_o,
  output gf_status_e         status_o,

  output logic               idle_o
);

  typedef enum logic [1:0] {S_IDLE, S_RUN, S_FINAL, S_DONE} state_e;
  state_e state_q;

  localparam int unsigned CNT_W = $clog2(DIVSTEP_BOUND + 1);
  // delta stays within +/- (DIVSTEP_BOUND+1); size generously
  localparam int unsigned DW = CNT_W + 2;

  // spec-mandated register set
  logic signed [DW-1:0]      delta_q;
  logic signed [WIDTH+1:0]   f_q, g_q;     // signed, WIDTH+1 magnitude bits
  logic [WIDTH-1:0]          v_q, r_q;     // cofactors mod m
  logic [WIDTH-1:0]          m_q;
  logic [CNT_W-1:0]          cnt_q;
  logic [WIDTH-1:0]          result_q;
  gf_status_e                status_q;

  // ---------------------------------------------------------------------------
  // one divstep, both paths computed, mux select = (delta > 0) && g odd
  // ---------------------------------------------------------------------------
  logic g_odd, swap_sel;
  assign g_odd    = g_q[0];
  assign swap_sel = (delta_q > 0) && g_odd;

  // path A (swap): f' = g ; g' = (g - f) >> 1 ; v' = r ; r' = half_mod(r - v)
  logic signed [WIDTH+1:0] g_minus_f;
  assign g_minus_f = g_q - f_q;

  // path B (keep): g' = (g + (g_odd ? f : 0)) >> 1 ; r' = half_mod(r + (g_odd ? v : 0))
  logic signed [WIDTH+1:0] g_plus_mf;
  assign g_plus_mf = g_q + (g_odd ? f_q : '0);

  // modular subtract / add for cofactors (operands < m)
  logic [WIDTH:0] rv_sub_raw, rv_sub_fix, rv_add_raw, rv_add_fix;
  assign rv_sub_raw = {1'b0, r_q} - {1'b0, v_q};
  assign rv_sub_fix = rv_sub_raw[WIDTH] ? rv_sub_raw + {1'b0, m_q} : rv_sub_raw;
  assign rv_add_raw = {1'b0, r_q} + (g_odd ? {1'b0, v_q} : '0);
  assign rv_add_fix = (rv_add_raw >= {1'b0, m_q}) ? rv_add_raw - {1'b0, m_q}
                                                  : rv_add_raw;

  // half_mod(x): x even ? x>>1 : (x+m)>>1   (m odd => x+m even)
  function automatic logic [WIDTH-1:0] half_mod(input logic [WIDTH:0] x,
                                                input logic [WIDTH-1:0] m);
    logic [WIDTH+1:0] t;
    t = x[0] ? ({1'b0, x} + {2'b00, m}) : {1'b0, x};
    return t[WIDTH:1];
  endfunction

  logic [WIDTH-1:0] r_next;
  assign r_next = swap_sel ? half_mod(rv_sub_fix, m_q)
                           : half_mod(rv_add_fix, m_q);

  // final correction: f == +1 -> v ; f == -1 -> m - v ; else not invertible
  logic f_is_p1, f_is_m1;
  assign f_is_p1 = (f_q == (WIDTH+2)'(1));
  assign f_is_m1 = (f_q == {(WIDTH+2){1'b1}});       // -1 two's complement
  logic [WIDTH:0] m_minus_v;
  assign m_minus_v = {1'b0, m_q} - {1'b0, v_q};
  // v may be 0 when inverse is 0? inverse of a=... v<m always; m-v==m only if v==0,
  // but f==+/-1 with v==0 cannot occur for valid inverse except m==1 (screened).
  logic [WIDTH:0] neg_v_fix;
  assign neg_v_fix = (v_q == '0) ? '0 : m_minus_v;

  assign ready_o  = (state_q == S_IDLE);
  assign valid_o  = (state_q == S_DONE);
  assign result_o = result_q;
  assign status_o = status_q;
  assign idle_o   = (state_q == S_IDLE);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q  <= S_IDLE;
      delta_q  <= '0;
      f_q      <= '0;
      g_q      <= '0;
      v_q      <= '0;
      r_q      <= '0;
      m_q      <= '0;
      cnt_q    <= '0;
      result_q <= '0;
      status_q <= STATUS_OK;
    end else begin
      unique case (state_q)
        S_IDLE: if (valid_i) begin
          delta_q <= DW'(1);
          f_q     <= {2'b00, m_i};
          g_q     <= {2'b00, a_i};
          v_q     <= '0;
          r_q     <= {{(WIDTH-1){1'b0}}, 1'b1};
          m_q     <= m_i;
          cnt_q   <= '0;
          state_q <= S_RUN;
        end
        S_RUN: begin
          if (swap_sel) begin
            delta_q <= DW'(1) - delta_q;
            f_q     <= g_q;
            g_q     <= g_minus_f >>> 1;
            v_q     <= r_q;
          end else begin
            delta_q <= delta_q + DW'(1);
            g_q     <= g_plus_mf >>> 1;
          end
          r_q   <= r_next;
          cnt_q <= cnt_q + 1'b1;
          if (cnt_q == CNT_W'(DIVSTEP_BOUND-1)) state_q <= S_FINAL;
        end
        S_FINAL: begin
          // fault countermeasure: the proof bound guarantees g == 0 here for
          // ALL legal inputs; g != 0 therefore implies a fault (glitch /
          // corrupted state) and must never yield a silent wrong answer
          if (g_q != '0) begin
            result_q <= '0;
            status_q <= STATUS_FAULT;
          end else if (f_is_p1) begin
            result_q <= v_q;
            status_q <= STATUS_OK;
          end else if (f_is_m1) begin
            result_q <= neg_v_fix[WIDTH-1:0];
            status_q <= STATUS_OK;
          end else begin
            result_q <= '0;
            status_q <= STATUS_NOT_INVERTIBLE;
          end
          state_q <= S_DONE;
        end
        S_DONE: if (ready_i) begin
          state_q <= S_IDLE;
          // secure wipe of cofactor/state registers
          f_q <= '0; g_q <= '0; v_q <= '0; r_q <= '0; result_q <= '0;
        end
        default: state_q <= S_IDLE;
      endcase
    end
  end

`ifdef GF_ASSERTIONS
  // termination invariant: g must be exactly 0 when bound exhausts
  a_g_terminated: assert property (@(posedge clk_i) disable iff (!rst_ni)
    (state_q == S_FINAL) |-> (g_q == '0));
`endif

endmodule
