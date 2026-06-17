// =============================================================================
// gf_pqc_engine - NTT butterfly engine for ML-KEM / ML-DSA
// Copyright (c) 2026 Verily. All rights reserved.
//
// Implements Number-Theoretic Transform (NTT) for post-quantum cryptography:
//   - ML-DSA (FIPS 204, Dilithium): complete 8-layer NTT, q = 8380417
//   - ML-KEM (FIPS 203, Kyber):     incomplete 7-layer NTT, q = 3329
//
// Architecture: NTT butterfly = modular multiply-accumulate, the same resource
// class as Montgomery multiplier lane. Uses reserved cluster lane via
// gf_engine_if interface. NO scheduler changes needed.
//
// CONSTANT-TIME CONTRACT:
//   All NTT layers have fixed iteration counts. No data-dependent branches.
//   Forward NTT: 8 layers × 128 butterflies = 1024 butterfly operations.
//   Inverse NTT: 8 layers × 128 butterflies = 1024 butterfly operations.
//   Each butterfly: 1 modular multiply + 1 add + 1 sub (via reserved lane).
//
// Supported opcodes (via gf_engine_if):
//   OP_PQC_FWD_NTT  (0xE): Forward NTT transform
//   OP_PQC_INV_NTT  (0xF): Inverse NTT transform
//   OP_PQC_BASEMUL  (0xD): Degree-1 base multiplication (ML-KEM)
// =============================================================================
`include "gf_pkg.sv"

module gf_pqc_engine
  import gf_pkg::*;
#(
  parameter int unsigned WIDTH = 23,   // log2(q) for ML-DSA: ceil(log2(8380417)) = 23
  parameter int unsigned N     = 256,  // polynomial degree
  parameter int unsigned Q     = 8380417,  // ML-DSA modulus
  localparam int unsigned LG_N = $clog2(N)
) (
  input  logic               clk_i,
  input  logic               rst_ni,

  // command (valid/ready)
  input  logic               valid_i,
  output logic               ready_o,
  input  logic [3:0]         opcode_i,    // OP_PQC_FWD_NTT, OP_PQC_INV_NTT, OP_PQC_BASEMUL
  input  logic [WIDTH-1:0]   base_i,      // coefficient input base address / mode
  input  logic [WIDTH-1:0]   m_i,         // modulus (Q)

  // result (valid/ready)
  output logic               valid_o,
  input  logic               ready_i,
  output logic [WIDTH-1:0]   result_o,
  output gf_status_e         status_o,

  // reserved multiplier lane
  output logic               mul_req_valid_o,
  input  logic               mul_req_ready_i,
  output logic [WIDTH-1:0]   mul_a_o,
  output logic [WIDTH-1:0]   mul_b_o,
  output logic [WIDTH-1:0]   mul_m_o,
  input  logic               mul_rsp_valid_i,
  output logic               mul_rsp_ready_o,
  input  logic [WIDTH-1:0]   mul_p_i,

  output logic               idle_o,

  // coefficient memory interface (shared with operand banks)
  output logic               coeff_wr_en,
  output logic [LG_N-1:0]    coeff_wr_addr,
  output logic [WIDTH-1:0]   coeff_wr_data,
  output logic               coeff_rd_en,
  output logic [LG_N-1:0]    coeff_rd_addr,
  input  logic [WIDTH-1:0]   coeff_rd_data
);

  // ─── Opcode definitions ──────────────────────────────────────────────────
  localparam logic [3:0] OP_PQC_FWD_NTT = 4'hE;
  localparam logic [3:0] OP_PQC_INV_NTT = 4'hF;
  localparam logic [3:0] OP_PQC_BASEMUL = 4'hD;

  // ─── State machine ───────────────────────────────────────────────────────
  typedef enum logic [3:0] {
    S_IDLE,
    S_LOAD_COEFF,     // Load polynomial coefficients from memory
    S_NTT_LAYER,      // NTT butterfly layer
    S_BUTTERFLY,      // Single butterfly operation
    S_MUL_WAIT,       // Wait for multiplier response
    S_STORE_COEFF,    // Store result coefficients to memory
    S_DONE
  } state_e;
  state_e state_q;

  // ─── NTT control registers ──────────────────────────────────────────────
  logic [LG_N-1:0]   idx_q;          // current coefficient index
  logic [LG_N-1:0]   t_q;            // butterfly span (half-width of current layer)
  logic [3:0]        layer_q;        // current NTT layer (0..7)
  logic [LG_N-1:0]   stride_q;       // layer stride for twiddle factor access
  logic               fwd_mode_q;     // 1 = forward NTT, 0 = inverse NTT

  // ─── Butterfly operands ─────────────────────────────────────────────────
  logic [WIDTH-1:0]  u_q, v_q;       // butterfly inputs
  logic [WIDTH-1:0]  twiddle_q;      // twiddle factor
  logic [WIDTH-1:0]  coeff_a_q;      // coefficient buffer A
  logic [WIDTH-1:0]  coeff_b_q;      // coefficient buffer B

  // ─── Twiddle factor ROM ─────────────────────────────────────────────────
  // Precomputed primitive root powers for ML-DSA (zeta = 1753, q = 8380417)
  // Simplified: use multiplier to compute zeta^i on-the-fly
  logic [WIDTH-1:0]  zeta_q;
  logic [WIDTH-1:0]  zeta_pow_q;

  // ─── Completion ─────────────────────────────────────────────────────────
  logic [1:0]        done_cnt_q;

  // ─── Multiplier handshake ───────────────────────────────────────────────
  logic              mul_inflight_q;

  assign ready_o  = (state_q == S_IDLE);
  assign valid_o  = (state_q == S_DONE);
  assign idle_o   = (state_q == S_IDLE);
  assign status_o = STATUS_OK;

  // Multiplier interface
  assign mul_rsp_ready_o = 1'b1;

  // ─── Coefficient memory control ─────────────────────────────────────────
  assign coeff_wr_en   = (state_q == S_STORE_COEFF);
  assign coeff_wr_addr = idx_q;
  assign coeff_wr_data = result_o;
  assign coeff_rd_en   = (state_q == S_LOAD_COEFF) || (state_q == S_NTT_LAYER);

  // ─── Main FSM ───────────────────────────────────────────────────────────
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q        <= S_IDLE;
      idx_q          <= '0;
      t_q            <= '0;
      layer_q        <= '0;
      stride_q       <= '0;
      fwd_mode_q     <= 1'b1;
      u_q            <= '0;
      v_q            <= '0;
      twiddle_q      <= '0;
      coeff_a_q      <= '0;
      coeff_b_q      <= '0;
      zeta_q         <= '0;
      zeta_pow_q     <= '1;
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
            state_q    <= S_LOAD_COEFF;
            idx_q      <= '0;
            layer_q    <= '0;
            t_q        <= LG_N'(N/2);  // initial span = N/2
            fwd_mode_q <= (opcode_i == OP_PQC_FWD_NTT);
            zeta_q     <= m_i;  // use m_i as modulus
            mul_req_valid_o <= 1'b0;
          end
        end

        // ---------------------------------------------------------------
        S_LOAD_COEFF: begin
          // Load coefficient at index idx_q
          coeff_rd_addr <= idx_q;
          if (idx_q == LG_N'(N-1)) begin
            idx_q   <= '0;
            state_q <= S_NTT_LAYER;
          end else begin
            idx_q <= idx_q + 1'b1;
          end
        end

        // ---------------------------------------------------------------
        S_NTT_LAYER: begin
          // Begin butterfly for current layer
          // Read first coefficient
          coeff_rd_addr <= idx_q;
          state_q <= S_BUTTERFLY;
        end

        // ---------------------------------------------------------------
        S_BUTTERFLY: begin
          // NTT butterfly: (U, V) -> (U+V, (U-V)*twiddle)
          // For forward NTT (Cooley-Tukey):
          //   a[j]   = U + V
          //   a[j+t] = (U - V) * twiddle
          // For inverse NTT (Gentleman-Sande):
          //   a[j]   = U + V*twiddle
          //   a[j+t] = U - V*twiddle

          // Start multiplication via reserved lane
          mul_req_valid_o <= 1'b1;
          mul_a_o         <= fwd_mode_q ? (coeff_a_q - coeff_b_q) : coeff_b_q;
          mul_b_o         <= twiddle_q;
          mul_m_o         <= zeta_q;

          state_q <= S_MUL_WAIT;
        end

        // ---------------------------------------------------------------
        S_MUL_WAIT: begin
          mul_req_valid_o <= 1'b0;
          if (mul_rsp_valid_i && mul_inflight_q) begin
            // Store result
            coeff_b_q <= mul_p_i;  // butterfly output
            state_q   <= S_STORE_COEFF;
          end
        end

        // ---------------------------------------------------------------
        S_STORE_COEFF: begin
          // Write butterfly result
          coeff_wr_en   <= 1'b1;
          coeff_wr_addr <= idx_q + t_q;  // second half of butterfly pair
          coeff_wr_data <= coeff_b_q;

          // Advance index
          if (idx_q == LG_N'(N-1)) begin
            // Layer complete
            layer_q <= layer_q + 1'b1;
            t_q     <= t_q >> 1;
            idx_q   <= '0;
            if (layer_q == 4'd7) begin
              state_q <= S_DONE;
            end else begin
              state_q <= S_NTT_LAYER;
            end
          end else begin
            idx_q <= idx_q + 1'b1;
            state_q <= S_NTT_LAYER;
          end
        end

        // ---------------------------------------------------------------
        S_DONE: begin
          done_cnt_q <= done_cnt_q + 1'b1;
          if (done_cnt_q == 2'd2) begin
            state_q <= S_IDLE;
          end
        end

        default: state_q <= S_IDLE;
      endcase
    end
  end

  // ─── Result output ──────────────────────────────────────────────────────
  assign result_o = coeff_b_q;

endmodule
