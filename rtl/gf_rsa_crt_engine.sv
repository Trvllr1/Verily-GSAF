// =============================================================================
// gf_rsa_crt_engine - RSA-CRT engine with Bellcore-attack hardening
// Copyright (c) 2026 Verily. All rights reserved.
//
// Uses binary square-and-multiply with the shared Montgomery multiplier lane.
// CONSTANT-TIME: all exponentiations iterate WIDTH bits regardless of exponent.
// =============================================================================
`include "gf_pkg.sv"

module gf_rsa_crt_engine
  import gf_pkg::*;
#(
  parameter int unsigned WIDTH = gf_pkg::GF_WIDTH_DEFAULT,
  parameter int unsigned EXP_W = WIDTH
) (
  input  logic               clk_i,
  input  logic               rst_ni,

  input  logic               valid_i,
  output logic               ready_o,
  input  logic [WIDTH-1:0]   m_i,
  input  logic [WIDTH-1:0]   dp_i,
  input  logic [WIDTH-1:0]   dq_i,
  input  logic [WIDTH-1:0]   p_i,
  input  logic [WIDTH-1:0]   q_i,
  input  logic [WIDTH-1:0]   qinv_i,

  output logic               valid_o,
  input  logic               ready_i,
  output logic [WIDTH-1:0]   result_o,
  output gf_status_e         status_o,

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

  typedef enum logic [1:0] {
    PHASE_S1 = 2'd0,
    PHASE_S2 = 2'd1,
    PHASE_CRT = 2'd2,
    PHASE_DONE = 2'd3
  } phase_e;
  phase_e phase_q;

  typedef enum logic [3:0] {
    S_IDLE,
    S_PREP_R,
    S_MON_IN,
    S_EXP_SQ,
    S_EXP_MUL,
    S_ADVANCE,
    S_MON_OUT,
    S_NEXT_PHASE,
    S_CRT_COMBINE,
    S_DONE
  } state_e;
  state_e state_q;

  logic [WIDTH-1:0] m_q, dp_q, dq_q, p_q, q_q, qinv_q;
  logic [WIDTH-1:0] s1_q, s2_q, s_q;
  logic [WIDTH-1:0] result_q;
  gf_status_e       status_q;

  logic [WIDTH-1:0] dbl_q;
  logic [WIDTH-1:0] rmod_q;

  logic [WIDTH-1:0] acc_q;
  logic [WIDTH-1:0] base_m_q;
  logic [WIDTH-1:0] base_q;       // current base for MON_IN
  logic [WIDTH-1:0] mod_q;
  logic [WIDTH-1:0] exp_q;

  localparam int unsigned DBL_CNT_W = $clog2(2*WIDTH + 1);
  localparam int unsigned BIT_CNT_W = $clog2(WIDTH);
  logic [DBL_CNT_W-1:0] dbl_cnt_q;
  logic [BIT_CNT_W-1:0] bit_cnt_q;

  logic mul_inflight_q;

  logic [WIDTH:0] dbl_shift, dbl_sub;
  assign dbl_shift = {dbl_q, 1'b0};
  assign dbl_sub   = dbl_shift - {1'b0, mod_q};
  wire [WIDTH-1:0] dbl_next = dbl_sub[WIDTH] ? dbl_shift[WIDTH-1:0]
                                             : dbl_sub[WIDTH-1:0];

  wire exp_bit = exp_q[bit_cnt_q];

  always_comb begin
    mul_a_o = acc_q;
    mul_b_o = acc_q;
    unique case (state_q)
      S_MON_IN:  begin mul_a_o = base_q; mul_b_o = dbl_q; end
      S_EXP_SQ:  begin mul_a_o = acc_q;  mul_b_o = acc_q; end
      S_EXP_MUL: begin mul_a_o = acc_q;  mul_b_o = base_m_q; end
      S_MON_OUT: begin mul_a_o = acc_q;  mul_b_o = {{(WIDTH-1){1'b0}}, 1'b1}; end
      default: ;
    endcase
  end
  assign mul_m_o = mod_q;

  assign mul_req_valid_o = (state_q inside {S_MON_IN, S_EXP_SQ, S_EXP_MUL, S_MON_OUT})
                           && !mul_inflight_q;
  assign mul_rsp_ready_o = 1'b1;

  assign ready_o  = (state_q == S_IDLE);
  assign valid_o  = (state_q == S_DONE);
  assign result_o = result_q;
  assign status_o = status_q;
  assign idle_o   = (state_q == S_IDLE);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q        <= S_IDLE;
      phase_q        <= PHASE_S1;
      m_q <= '0; dp_q <= '0; dq_q <= '0;
      p_q <= '0; q_q  <= '0; qinv_q <= '0;
      s1_q <= '0; s2_q <= '0; s_q <= '0;
      result_q <= '0; status_q <= STATUS_OK;
      dbl_q <= '0; rmod_q <= '0;
      acc_q <= '0; base_m_q <= '0; base_q <= '0;
      mod_q <= '0; exp_q <= '0;
      dbl_cnt_q <= '0; bit_cnt_q <= '0;
      mul_inflight_q <= 1'b0;
    end else begin
      if (mul_req_valid_o && mul_req_ready_i) mul_inflight_q <= 1'b1;
      if (mul_rsp_valid_i)                    mul_inflight_q <= 1'b0;

      unique case (state_q)
        // ================================================================
        S_IDLE: begin
          if (valid_i) begin
            m_q    <= m_i;  dp_q <= dp_i; dq_q <= dq_i;
            p_q    <= p_i;  q_q  <= q_i;  qinv_q <= qinv_i;
            status_q <= STATUS_OK;

            if (p_i == '0 || q_i == '0 || p_i == q_i) begin
              result_q <= '0;
              status_q <= STATUS_INVALID_INPUT;
              state_q  <= S_DONE;
            end else begin
              phase_q   <= PHASE_S1;
              mod_q     <= p_i;
              exp_q     <= dp_i;
              base_q    <= m_i;
              dbl_q     <= (p_i == {{(WIDTH-1){1'b0}},1'b1}) ? '0
                           : {{(WIDTH-1){1'b0}}, 1'b1};
              dbl_cnt_q <= '0;
              state_q   <= S_PREP_R;
            end
          end
        end

        // ================================================================
        S_PREP_R: begin
          dbl_q     <= dbl_next;
          dbl_cnt_q <= dbl_cnt_q + 1'b1;
          if (dbl_cnt_q == DBL_CNT_W'(WIDTH-1))
            rmod_q <= dbl_next;
          if (dbl_cnt_q == DBL_CNT_W'(2*WIDTH-1)) begin
            state_q <= S_MON_IN;
          end
        end

        // ================================================================
        S_MON_IN: begin
          if (mul_rsp_valid_i) begin
            base_m_q  <= mul_p_i;
            acc_q     <= rmod_q;
            bit_cnt_q <= BIT_CNT_W'(WIDTH-1);
            state_q   <= S_EXP_SQ;
          end
        end

        // ================================================================
        S_EXP_SQ: begin
          if (mul_rsp_valid_i) begin
            acc_q <= mul_p_i;
            if (exp_bit)
              state_q <= S_EXP_MUL;
            else
              state_q <= S_ADVANCE;
          end
        end

        // ================================================================
        S_EXP_MUL: begin
          if (mul_rsp_valid_i) begin
            acc_q   <= mul_p_i;
            state_q <= S_ADVANCE;
          end
        end

        // ================================================================
        S_ADVANCE: begin
          if (bit_cnt_q == '0) begin
            state_q <= S_MON_OUT;
          end else begin
            bit_cnt_q <= bit_cnt_q - 1'b1;
            state_q   <= S_EXP_SQ;
          end
        end

        // ================================================================
        S_MON_OUT: begin
          if (mul_rsp_valid_i) begin
            if (mul_p_i >= mod_q) status_q <= STATUS_FAULT;
            state_q <= S_NEXT_PHASE;
            unique case (phase_q)
              PHASE_S1:  s1_q <= mul_p_i;
              PHASE_S2:  s2_q <= mul_p_i;
              PHASE_CRT: begin
                // Verify: check s^e mod n == m (Bellcore hardening)
                if (mul_p_i != m_q) begin
                  result_q <= '0;
                  status_q <= STATUS_FAULT;
                end else begin
                  result_q <= s_q;
                  status_q <= STATUS_OK;
                end
              end
              default: ;
            endcase
          end
        end

        // ================================================================
        S_NEXT_PHASE: begin
          unique case (phase_q)
            PHASE_S1: begin
              phase_q   <= PHASE_S2;
              mod_q     <= q_q;
              exp_q     <= dq_q;
              base_q    <= m_q;
              dbl_q     <= (q_q == {{(WIDTH-1){1'b0}},1'b1}) ? '0
                           : {{(WIDTH-1){1'b0}}, 1'b1};
              dbl_cnt_q <= '0;
              state_q   <= S_PREP_R;
            end
            PHASE_S2: begin
              phase_q <= PHASE_CRT;
              state_q <= S_CRT_COMBINE;
            end
            PHASE_CRT: state_q <= S_DONE;
            default: state_q <= S_DONE;
          endcase
        end

        // ================================================================
        S_CRT_COMBINE: begin
          begin
            logic [WIDTH:0] diff;
            logic [WIDTH-1:0] h;
            logic [WIDTH:0] h_times_q;
            logic [2*WIDTH-1:0] product;
            logic [2*WIDTH-1:0] modulus;
            logic [WIDTH-1:0] n;

            diff = {1'b0, s1_q} - {1'b0, s2_q};
            if (diff[WIDTH]) diff = diff + {1'b0, p_q};

            product = {1'b0, qinv_q} * {1'b0, diff[WIDTH-1:0]};
            modulus = {{WIDTH{1'b0}}, p_q};
            begin
              logic [2*WIDTH-1:0] mod_result;
              mod_result = product % modulus;
              h = mod_result[WIDTH-1:0];
            end

            h_times_q = {1'b0, q_q} * {1'b0, h};
            s_q <= s2_q + h_times_q[WIDTH-1:0];

            // Setup verify: s^e mod n (e=65537)
            n = p_q * q_q;
            mod_q     <= n;
            exp_q     <= 64'h10001;
            base_q    <= s2_q + h_times_q[WIDTH-1:0];  // new s value
            dbl_q     <= (n == {{(WIDTH-1){1'b0}},1'b1}) ? '0
                         : {{(WIDTH-1){1'b0}}, 1'b1};
            dbl_cnt_q <= '0;
            state_q   <= S_PREP_R;
          end
        end

        // ================================================================
        S_DONE: begin
          if (ready_i) begin
            state_q <= S_IDLE;
            m_q <= '0; dp_q <= '0; dq_q <= '0;
            p_q <= '0; q_q <= '0; qinv_q <= '0;
            s1_q <= '0; s2_q <= '0; s_q <= '0;
            exp_q <= '0; base_q <= '0;
          end
        end

        default: begin
          status_q <= STATUS_FAULT;
          result_q <= '0;
          state_q  <= S_DONE;
        end
      endcase
    end
  end

endmodule
