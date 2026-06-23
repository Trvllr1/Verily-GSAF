// =============================================================================
// gf_ecc_engine - Elliptic curve cryptography engine
// Copyright (c) 2026 Verily. All rights reserved.
//
// Implements X25519 Diffie-Hellman key exchange (RFC 7748).
// Uses constant-time Montgomery ladder: 4 field multiplications per bit.
// =============================================================================
`include "gf_pkg.sv"

module gf_ecc_engine
  import gf_pkg::*;
#(
  parameter int unsigned WIDTH = 255,
  parameter int unsigned CURVE_TYPE = 0
) (
  input  logic               clk_i,
  input  logic               rst_ni,

  input  logic               valid_i,
  output logic               ready_o,
  input  logic [3:0]         opcode_i,
  input  logic [WIDTH-1:0]   base_i,
  input  logic [WIDTH-1:0]   exp_i,
  input  logic [WIDTH-1:0]   m_i,

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

  typedef enum logic [3:0] {
    S_IDLE,
    S_CLAMP,
    S_LADDER_SQ0,
    S_LADDER_SQ1,
    S_LADDER_MUL0,
    S_LADDER_MUL1,
    S_DONE
  } state_e;
  state_e state_q;

  logic [WIDTH-1:0] scalar_q;
  logic [WIDTH-1:0] result_q;
  gf_status_e       status_q;

  logic [WIDTH-1:0] x_0_q, x_1_q;
  logic [WIDTH-1:0] t0_q, t1_q;
  logic [WIDTH-1:0] t2_q, t3_q;
  logic [WIDTH-1:0] t4_q, t5_q;
  logic [8:0]       bit_cnt_q;
  logic [1:0]       step_q;

  logic [1:0]       done_cnt_q;

  localparam logic [WIDTH-1:0] X25519_P   = {1'b1, {(WIDTH-1){1'b0}}} - 19;
  localparam logic [WIDTH-1:0] X25519_A24 = 121666;

  assign ready_o  = (state_q == S_IDLE);
  assign valid_o  = (state_q == S_DONE);
  assign result_o = result_q;
  assign status_o = status_q;
  assign idle_o   = (state_q == S_IDLE);

  assign mul_rsp_ready_o = 1'b1;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q        <= S_IDLE;
      scalar_q       <= '0;
      result_q       <= '0;
      status_q       <= STATUS_OK;
      x_0_q          <= '0;
      x_1_q          <= '0;
      t0_q           <= '0;
      t1_q           <= '0;
      t2_q           <= '0;
      t3_q           <= '0;
      t4_q           <= '0;
      t5_q           <= '0;
      bit_cnt_q      <= '0;
      step_q         <= '0;
      done_cnt_q     <= '0;
      mul_req_valid_o <= 1'b0;
      mul_a_o        <= '0;
      mul_b_o        <= '0;
      mul_m_o        <= '0;
    end else begin
      unique case (state_q)
        S_IDLE: begin
          if (valid_i) begin
            status_q <= STATUS_OK;
            unique case (opcode_i)
              OP_X25519: begin
                x_0_q <= exp_i;
                x_1_q <= '0;
                x_1_q[0] <= 1'b1;
                state_q <= S_CLAMP;
              end
              OP_ECC_PADD, OP_ECC_PDBL, OP_ED25519: begin
                status_q <= STATUS_UNSUPPORTED;
                state_q  <= S_DONE;
              end
              default: begin
                status_q <= STATUS_UNSUPPORTED;
                state_q  <= S_DONE;
              end
            endcase
          end
        end

        // RFC 7748 clamping: clear bits 0-2, set bit 254, clear bit 255
        S_CLAMP: begin
          scalar_q <= (base_i & ~({{(WIDTH-3){1'b0}}, 3'b111})
                           & ~({{1'b1}, {(WIDTH-1){1'b0}}}))
                      | ({{(WIDTH-1){1'b0}}, 1'b1} << 254);
          bit_cnt_q <= 9'd254;
          step_q    <= 2'd0;
          state_q   <= S_LADDER_SQ0;
        end

        // Montgomery ladder: 4 muls per bit
        S_LADDER_SQ0: begin
          t0_q <= x_0_q + x_1_q;
          t1_q <= x_0_q - x_1_q;

          mul_req_valid_o <= 1'b1;
          mul_a_o         <= x_0_q + x_1_q;
          mul_b_o         <= x_0_q + x_1_q;
          mul_m_o         <= X25519_P;

          if (mul_rsp_valid_i) begin
            t2_q            <= mul_p_i;
            mul_req_valid_o <= 1'b0;
            state_q         <= S_LADDER_SQ1;
          end
        end

        S_LADDER_SQ1: begin
          mul_req_valid_o <= 1'b1;
          mul_a_o         <= t1_q;
          mul_b_o         <= t1_q;
          mul_m_o         <= X25519_P;

          if (mul_rsp_valid_i) begin
            t3_q            <= mul_p_i;
            t4_q            <= t2_q - mul_p_i;
            mul_req_valid_o <= 1'b0;
            step_q          <= 2'd0;
            state_q         <= S_LADDER_MUL0;
          end
        end

        // t5 = A24 * t4 mod p
        S_LADDER_MUL0: begin
          if (step_q == 2'd0) begin
            mul_req_valid_o <= 1'b1;
            mul_a_o         <= X25519_A24;
            mul_b_o         <= t4_q;
            mul_m_o         <= X25519_P;
            step_q          <= 2'd1;
          end else if (mul_rsp_valid_i) begin
            t5_q            <= mul_p_i;
            mul_req_valid_o <= 1'b0;
            step_q          <= 2'd0;
            state_q         <= S_LADDER_MUL1;
          end
        end

        // x_0_new = t2 * (t3 + t5), x_1_new = t4 * (t2 + t5)
        S_LADDER_MUL1: begin
          if (step_q == 2'd0) begin
            mul_req_valid_o <= 1'b1;
            mul_a_o         <= t2_q;
            mul_b_o         <= t3_q + t5_q;
            mul_m_o         <= X25519_P;
            step_q          <= 2'd1;
          end else if (mul_rsp_valid_i && step_q == 2'd1) begin
            x_0_q           <= mul_p_i;
            mul_req_valid_o <= 1'b1;
            mul_a_o         <= t4_q;
            mul_b_o         <= t2_q + t5_q;
            mul_m_o         <= X25519_P;
            step_q          <= 2'd2;
          end else if (mul_rsp_valid_i && step_q == 2'd2) begin
            mul_req_valid_o <= 1'b0;

            // Constant-time conditional swap
            begin
              logic [WIDTH-1:0] x0_new, x1_new, final_x0;
              x0_new  = scalar_q[bit_cnt_q[7:0]] ? mul_p_i : x_0_q;
              x1_new  = scalar_q[bit_cnt_q[7:0]] ? x_0_q   : mul_p_i;
              final_x0 = (bit_cnt_q == 9'd0) ? x0_new : x_0_q;
              x_0_q   <= x0_new;
              x_1_q   <= x1_new;
              result_q <= final_x0;
            end

            if (bit_cnt_q == 9'd0) begin
              state_q <= S_DONE;
            end else begin
              bit_cnt_q <= bit_cnt_q - 1'b1;
              step_q    <= 2'd0;
              state_q   <= S_LADDER_SQ0;
            end
          end
        end

        S_DONE: begin
          done_cnt_q <= done_cnt_q + 1'b1;
          if (done_cnt_q == 2'd2) begin
            state_q <= S_IDLE;
            scalar_q <= '0;
            x_0_q    <= '0;
            x_1_q    <= '0;
            t0_q <= '0; t1_q <= '0;
            t2_q <= '0; t3_q <= '0;
            t4_q <= '0; t5_q <= '0;
          end
        end

        default: state_q <= S_IDLE;
      endcase
    end
  end

endmodule
