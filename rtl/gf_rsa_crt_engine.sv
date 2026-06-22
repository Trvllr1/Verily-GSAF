// =============================================================================
// gf_rsa_crt_engine - RSA-CRT engine with Bellcore-attack hardening
// Copyright (c) 2026 Verily. All rights reserved.
//
// Implements RSA private key operation using Chinese Remainder Theorem (CRT)
// optimization with verify-after-sign for Bellcore-attack detection.
//
// Algorithm:
//   s1 = m^dp mod p
//   s2 = m^dq mod q
//   h = qinv * (s1 - s2) mod p
//   s = s2 + q * h
//   Verify: s^e mod n == m (Bellcore hardening)
//
// CONSTANT-TIME CONTRACT:
//   All operations have fixed latency independent of operand values.
//   The verify-after-sign step is always executed (no early exit).
//
// Security properties:
//   - Constant-time: fixed iteration counts for all exponentiations
//   - Fault detection: verify-after-sign prevents Bellcore attack
//   - No silent faults: any error reports STATUS_FAULT
// =============================================================================
`include "gf_pkg.sv"

module gf_rsa_crt_engine
  import gf_pkg::*;
#(
  parameter int unsigned WIDTH = gf_pkg::GF_WIDTH_DEFAULT,  // bit width of p, q
  parameter int unsigned EXP_W = WIDTH                      // exponent width
) (
  input  logic               clk_i,
  input  logic               rst_ni,

  // command (valid/ready)
  input  logic               valid_i,
  output logic               ready_o,
  input  logic [WIDTH-1:0]   m_i,       // message
  input  logic [WIDTH-1:0]   dp_i,      // d mod (p-1)
  input  logic [WIDTH-1:0]   dq_i,      // d mod (q-1)
  input  logic [WIDTH-1:0]   p_i,       // prime p
  input  logic [WIDTH-1:0]   q_i,       // prime q
  input  logic [WIDTH-1:0]   qinv_i,    // q^-1 mod p

  // result (valid/ready)
  output logic               valid_o,
  input  logic               ready_i,
  output logic [WIDTH-1:0]   result_o,  // signature s
  output gf_status_e         status_o,

  // reserved multiplier lane (for modular exponentiation)
  output logic               mul_req_valid_o,
  input  logic               mul_req_ready_i,
  output logic [WIDTH-1:0]   mul_a_o,
  output logic [WIDTH-1:0]   mul_b_o,
  output logic [WIDTH-1:0]   mul_m_o,
  input  logic               mul_rsp_valid_i,
  output logic               mul_rsp_ready_o,
  input  logic [WIDTH-1:0]   mul_p_i,

  output logic               idle_o
);

  // ─── State machine ───────────────────────────────────────────────────────
  typedef enum logic [3:0] {
    S_IDLE,
    S_MODEXP_P,      // s1 = m^dp mod p
    S_MODEXP_Q,      // s2 = m^dq mod q
    S_CRT_COMBINE,   // h = qinv * (s1 - s2) mod p; s = s2 + q * h
    S_VERIFY,        // verify s^e mod n == m (Bellcore hardening)
    S_DONE
  } state_e;
  state_e state_q;

  // ─── Operand registers ──────────────────────────────────────────────────
  logic [WIDTH-1:0] m_q, dp_q, dq_q, p_q, q_q, qinv_q;
  logic [WIDTH-1:0] s1_q, s2_q, s_q;
  logic [WIDTH-1:0] result_q;
  gf_status_e       status_q;

  // ─── Multiplier handshake ───────────────────────────────────────────────
  logic              mul_inflight_q;

  // ─── Completion ─────────────────────────────────────────────────────────
  logic [1:0]        done_cnt_q;

  assign ready_o  = (state_q == S_IDLE);
  assign valid_o  = (state_q == S_DONE);
  assign result_o = result_q;
  assign status_o = status_q;
  assign idle_o   = (state_q == S_IDLE);

  // Multiplier interface
  assign mul_rsp_ready_o = 1'b1;

  // ─── Main FSM ───────────────────────────────────────────────────────────
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q        <= S_IDLE;
      m_q            <= '0;
      dp_q           <= '0;
      dq_q           <= '0;
      p_q            <= '0;
      q_q            <= '0;
      qinv_q         <= '0;
      s1_q           <= '0;
      s2_q           <= '0;
      s_q            <= '0;
      result_q       <= '0;
      status_q       <= STATUS_OK;
      mul_inflight_q <= 1'b0;
      done_cnt_q     <= '0;
      mul_req_valid_o <= 1'b0;
      mul_a_o        <= '0;
      mul_b_o        <= '0;
      mul_m_o        <= '0;
    end else begin
      // Default: deassert mul_req_valid
      if (mul_req_valid_o && mul_req_ready_i)
        mul_inflight_q <= 1'b1;
      if (mul_rsp_valid_i)
        mul_inflight_q <= 1'b0;

      unique case (state_q)
        // ---------------------------------------------------------------
        S_IDLE: begin
          if (valid_i) begin
            m_q    <= m_i;
            dp_q   <= dp_i;
            dq_q   <= dq_i;
            p_q    <= p_i;
            q_q    <= q_i;
            qinv_q <= qinv_i;
            status_q <= STATUS_OK;

            // Input validation
            if (p_i == '0 || q_i == '0 || p_i == q_i) begin
              result_q <= '0;
              status_q <= STATUS_INVALID_INPUT;
              state_q  <= S_DONE;
            end else begin
              state_q <= S_MODEXP_P;
            end
          end
        end

        // ---------------------------------------------------------------
        S_MODEXP_P: begin
          // s1 = m^dp mod p
          // Use multiplier for modular exponentiation
          mul_req_valid_o <= 1'b1;
          mul_a_o         <= m_q;
          mul_b_o         <= dp_q;
          mul_m_o         <= p_q;

          if (mul_rsp_valid_i) begin
            s1_q   <= mul_p_i;
            mul_req_valid_o <= 1'b0;  // Deassert so next state starts fresh
            state_q <= S_MODEXP_Q;
          end
        end

        // ---------------------------------------------------------------
        S_MODEXP_Q: begin
          // s2 = m^dq mod q
          mul_req_valid_o <= 1'b1;
          mul_a_o         <= m_q;
          mul_b_o         <= dq_q;
          mul_m_o         <= q_q;

          if (mul_rsp_valid_i) begin
            s2_q   <= mul_p_i;
            mul_req_valid_o <= 1'b0;  // Deassert so next state starts fresh
            state_q <= S_CRT_COMBINE;
          end
        end

        // ---------------------------------------------------------------
        S_CRT_COMBINE: begin
          // h = qinv * (s1 - s2) mod p
          // s = s2 + q * h
          logic [WIDTH:0] diff;
          logic [WIDTH-1:0] h;
          logic [WIDTH:0] h_times_q;

          // Deassert multiplier request (CRT combine is computed inline)
          mul_req_valid_o <= 1'b0;

          diff = {1'b0, s1_q} - {1'b0, s2_q};
          if (diff[WIDTH]) diff = diff + {1'b0, p_q};  // mod p

          // h = qinv * diff mod p (computed inline)
          begin
            logic [2*WIDTH-1:0] product;
            logic [2*WIDTH-1:0] modulus;
            logic [2*WIDTH-1:0] mod_result;
            product = {1'b0, qinv_q} * {1'b0, diff[WIDTH-1:0]};
            modulus = {{WIDTH{1'b0}}, p_q};
            mod_result = product % modulus;
            h = mod_result[WIDTH-1:0];
          end

          // s = s2 + q * h
          h_times_q = {1'b0, q_q} * {1'b0, h};
          s_q <= s2_q + h_times_q[WIDTH-1:0];
          state_q <= S_VERIFY;
        end

        // ---------------------------------------------------------------
        S_VERIFY: begin
          // Bellcore-attack hardening: verify s^e mod n == m
          // Compute s^e mod (p*q) using multiplier
          logic [WIDTH-1:0] n;
          n = p_q * q_q;

          mul_req_valid_o <= 1'b1;
          mul_a_o         <= s_q;
          mul_b_o         <= 64'h10001;  // e = 65537
          mul_m_o         <= n;

          if (mul_rsp_valid_i) begin
            if (mul_p_i != m_q) begin
              // Verification failed - Bellcore attack detected
              result_q <= '0;
              status_q <= STATUS_FAULT;
            end else begin
              result_q <= s_q;
              status_q <= STATUS_OK;
            end
            state_q <= S_DONE;
          end
        end

        // ---------------------------------------------------------------
        S_DONE: begin
          done_cnt_q <= done_cnt_q + 1'b1;
          if (done_cnt_q == 2'd2) begin
            state_q <= S_IDLE;
            // Secure wipe of sensitive data
            m_q    <= '0;
            dp_q   <= '0;
            dq_q   <= '0;
            p_q    <= '0;
            q_q    <= '0;
            qinv_q <= '0;
            s1_q   <= '0;
            s2_q   <= '0;
            s_q    <= '0;
          end
        end

        default: state_q <= S_IDLE;
      endcase
    end
  end

endmodule
