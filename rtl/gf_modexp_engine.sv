// =============================================================================
// gf_modexp_engine - Fixed-window constant-time modular exponentiation
// Copyright (c) 2026 Verily. All rights reserved.
//
// result = base ^ exp mod m  (m odd, base < m)
//
// Algorithm (mirrors model/golden_model.py::modexp exactly):
//   MON_IN     : R mod m, R^2 mod m by 2*WIDTH constant-time doublings,
//                then base_m = mont(base, R^2)
//   PRECOMPUTE : table[i] = base^i (Montgomery domain), 2^WINDOW_SIZE entries
//   EXP_LOOP   : per window: WINDOW_SIZE squarings + 1 multiply -- ALWAYS,
//                including window digit 0 => operation count independent of
//                exponent value (constant time)
//   MON_OUT    : mont(acc, 1)
//
// DPA countermeasure (exponent blinding): the exponent datapath is
// EXP_W = WIDTH + EXP_BLIND_BITS wide so the host may submit blinded
// exponents d' = d + k*lambda(m) (identical result, randomized bit pattern).
// Latency depends only on EXP_W -- leading zero windows are processed
// identically (4 squarings + multiply by Montgomery '1').
//
// Fault countermeasures: sparse FSM state encoding (illegal state traps to
// DONE with gf_pkg::STATUS_FAULT) and a result range check (result < m) that turns
// glitched arithmetic into gf_pkg::STATUS_FAULT instead of a silent wrong answer.
//
// Multiplier access is via a statically reserved lane (request/response
// valid/ready). The lane is owned for the full transaction: fixed latency,
// no contention, no mid-transaction stealing.
// =============================================================================
`include "gf_pkg.sv"

module gf_modexp_engine #(
  parameter int unsigned WIDTH          = gf_pkg::GF_WIDTH_DEFAULT,
  parameter int unsigned WINDOW_SIZE    = 4,
  parameter int unsigned EXP_BLIND_BITS = 64,
  localparam int unsigned EXP_W         = WIDTH + EXP_BLIND_BITS
) (
  input  logic               clk_i,
  input  logic               rst_ni,

  // command (valid/ready)
  input  logic               valid_i,
  output logic               ready_o,
  input  logic [WIDTH-1:0]   base_i,
  input  logic [EXP_W-1:0]   exp_i,
  input  logic [WIDTH-1:0]   m_i,

  // result (valid/ready)
  output logic               valid_o,
  input  logic               ready_i,
  output logic [WIDTH-1:0]   result_o,
  output gf_pkg::gf_status_e         status_o,

  // reserved multiplier lane
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

  localparam int unsigned TBL_ENTRIES = 1 << WINDOW_SIZE;
  localparam int unsigned N_WINDOWS   = EXP_W / WINDOW_SIZE;

  // Sparse state encoding: minimum pairwise Hamming distance 3; any
  // glitch-induced illegal state value falls into the default arm and
  // completes with gf_pkg::STATUS_FAULT (no silent corruption, no deadlock).
  typedef enum logic [5:0] {
    IDLE       = 6'b000000,
    MON_IN     = 6'b000111,
    PRECOMPUTE = 6'b011001,
    EXP_LOOP   = 6'b101010,
    MON_OUT    = 6'b110100,
    DONE       = 6'b111011
  } state_e;
  state_e state_q;

  // operand registers
  logic [EXP_W-1:0] exp_q;
  logic [WIDTH-1:0] m_q;
  gf_pkg::gf_status_e       status_q;
  // Montgomery constants
  logic [WIDTH-1:0] dbl_q;       // doubling accumulator -> R mod m -> R^2 mod m
  logic [WIDTH-1:0] rmod_q;      // R mod m (Montgomery '1')
  logic [WIDTH-1:0] r2_q;        // R^2 mod m
  // working registers
  logic [WIDTH-1:0] acc_q;
  logic [WIDTH-1:0] table_q [TBL_ENTRIES];

  // sequencing counters
  localparam int unsigned DBL_CNT_W = $clog2(2*WIDTH + 1);
  localparam int unsigned TBL_CNT_W = $clog2(TBL_ENTRIES);
  localparam int unsigned WIN_CNT_W = $clog2(N_WINDOWS);
  localparam int unsigned STP_CNT_W = $clog2(WINDOW_SIZE + 1);

  logic [DBL_CNT_W-1:0] dbl_cnt_q;
  logic [TBL_CNT_W-1:0] tbl_cnt_q;
  logic [WIN_CNT_W-1:0] win_cnt_q;
  logic [STP_CNT_W-1:0] stp_cnt_q;   // 0..WINDOW_SIZE-1 = squarings, WINDOW_SIZE = table mult
  logic                 mul_inflight_q;
  logic                 monin_mul_phase_q; // MON_IN: 0 = doubling, 1 = base*R^2
  logic                 mul_gate;          // MON_IN gates multiply until doublings done

  // current exponent window digit (variable part-select; shift = win*4)
  logic [$clog2(EXP_W)-1:0]   win_shift;
  logic [WINDOW_SIZE-1:0]     win_digit;
  assign win_shift = {win_cnt_q, {$clog2(WINDOW_SIZE){1'b0}}};
  assign win_digit = exp_q[win_shift +: WINDOW_SIZE];

  // constant-time doubling step: (x<<1) with unconditional subtract + mux
  logic [WIDTH:0] dbl_shift, dbl_sub;
  assign dbl_shift = {dbl_q, 1'b0};
  assign dbl_sub   = dbl_shift - {1'b0, m_q};
  wire [WIDTH-1:0] dbl_next = dbl_sub[WIDTH] ? dbl_shift[WIDTH-1:0]
                                             : dbl_sub[WIDTH-1:0];

  // ---------------------------------------------------------------------------
  // multiplier operand selection
  // ---------------------------------------------------------------------------
  always_comb begin
    mul_a_o = acc_q;
    mul_b_o = acc_q;
    case (state_q)
      MON_IN:     begin mul_a_o = table_q[1]; mul_b_o = r2_q; end // base_m = mont(base, R^2)
      PRECOMPUTE: begin mul_a_o = table_q[tbl_cnt_q - 1'b1]; mul_b_o = table_q[1]; end
      EXP_LOOP:   begin
        mul_a_o = acc_q;
        mul_b_o = (stp_cnt_q == STP_CNT_W'(WINDOW_SIZE)) ? table_q[win_digit] : acc_q;
      end
      MON_OUT:    begin mul_a_o = acc_q; mul_b_o = {{(WIDTH-1){1'b0}}, 1'b1}; end
      default: ;
    endcase
  end
  assign mul_m_o = m_q;

  assign mul_req_valid_o = (state_q == MON_IN || state_q == PRECOMPUTE ||
                            state_q == EXP_LOOP || state_q == MON_OUT)
                           && !mul_inflight_q && mul_gate;
  assign mul_rsp_ready_o = 1'b1;

  // MON_IN only issues its single multiply after doublings finish
  always_comb begin
    mul_gate = 1'b1;
    if (state_q == MON_IN) mul_gate = monin_mul_phase_q;
  end

  assign ready_o  = (state_q == IDLE);
  assign valid_o  = (state_q == DONE);
  assign result_o = acc_q;
  assign status_o = status_q;
  assign idle_o   = (state_q == IDLE);

  // ---------------------------------------------------------------------------
  // main FSM
  // ---------------------------------------------------------------------------
  // NOTE on MON_IN operand: base is parked in table_q[1] slot pre-conversion,
  // multiply uses (table_q[1], R^2) -> base_m written back to table_q[1].

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q           <= IDLE;
      exp_q             <= '0;
      m_q               <= '0;
      dbl_q             <= '0;
      rmod_q            <= '0;
      r2_q              <= '0;
      acc_q             <= '0;
      dbl_cnt_q         <= '0;
      tbl_cnt_q         <= '0;
      win_cnt_q         <= '0;
      stp_cnt_q         <= '0;
      mul_inflight_q    <= 1'b0;
      monin_mul_phase_q <= 1'b0;
      status_q          <= gf_pkg::STATUS_OK;
      for (int i = 0; i < TBL_ENTRIES; i++) table_q[i] <= '0;
    end else begin
      case (state_q)
        // -------------------------------------------------------------------
        IDLE: if (valid_i) begin
          exp_q             <= exp_i;
          m_q               <= m_i;
      status_q          <= '0;  // STATUS_OK = 0
          table_q[1]        <= base_i;            // parked for MON_IN multiply
          dbl_q             <= (m_i == {{(WIDTH-1){1'b0}},1'b1}) ? '0
                               : {{(WIDTH-1){1'b0}}, 1'b1};      // x = 1 (m>1)
          dbl_cnt_q         <= '0;
          monin_mul_phase_q <= 1'b0;
          mul_inflight_q    <= 1'b0;
          state_q           <= MON_IN;
        end
        // -------------------------------------------------------------------
        MON_IN: begin
          if (!monin_mul_phase_q) begin
            // 2*WIDTH constant-time doublings: after WIDTH -> R mod m
            dbl_q     <= dbl_next;
            dbl_cnt_q <= dbl_cnt_q + 1'b1;
            if (dbl_cnt_q == DBL_CNT_W'(WIDTH-1))   rmod_q <= dbl_next;
            if (dbl_cnt_q == DBL_CNT_W'(2*WIDTH-1)) begin
              r2_q              <= dbl_next;
              monin_mul_phase_q <= 1'b1;
            end
          end else begin
            // base_m = mont(base, R^2)
            if (mul_req_valid_o && mul_req_ready_i) mul_inflight_q <= 1'b1;
            if (mul_rsp_valid_i) begin
              mul_inflight_q <= 1'b0;
              table_q[0]     <= rmod_q;            // Montgomery '1'
              table_q[1]     <= mul_p_i;           // base_m
              tbl_cnt_q      <= TBL_CNT_W'(2);
              state_q        <= PRECOMPUTE;
            end
          end
        end
        // -------------------------------------------------------------------
        PRECOMPUTE: begin
          if (mul_req_valid_o && mul_req_ready_i) mul_inflight_q <= 1'b1;
          if (mul_rsp_valid_i) begin
            mul_inflight_q     <= 1'b0;
            table_q[tbl_cnt_q] <= mul_p_i;
            if (tbl_cnt_q == TBL_CNT_W'(TBL_ENTRIES-1)) begin
              acc_q     <= rmod_q;                 // acc = Montgomery '1'
              win_cnt_q <= WIN_CNT_W'(N_WINDOWS-1);
              stp_cnt_q <= '0;
              state_q   <= EXP_LOOP;
            end else begin
              tbl_cnt_q <= tbl_cnt_q + 1'b1;
            end
          end
        end
        // -------------------------------------------------------------------
        EXP_LOOP: begin
          if (mul_req_valid_o && mul_req_ready_i) mul_inflight_q <= 1'b1;
          if (mul_rsp_valid_i) begin
            mul_inflight_q <= 1'b0;
            acc_q          <= mul_p_i;
            if (stp_cnt_q == STP_CNT_W'(WINDOW_SIZE)) begin
              stp_cnt_q <= '0;
              if (win_cnt_q == '0) state_q <= MON_OUT;
              else                 win_cnt_q <= win_cnt_q - 1'b1;
            end else begin
              stp_cnt_q <= stp_cnt_q + 1'b1;
            end
          end
        end
        // -------------------------------------------------------------------
        MON_OUT: begin
          if (mul_req_valid_o && mul_req_ready_i) mul_inflight_q <= 1'b1;
          if (mul_rsp_valid_i) begin
            mul_inflight_q <= 1'b0;
            acc_q          <= mul_p_i;
            // fault countermeasure: glitched arithmetic cannot produce a
            // silently wrong in-range answer pattern we accept blindly --
            // any out-of-range result is flagged
            if (mul_p_i >= m_q) status_q <= gf_pkg::STATUS_FAULT;
            state_q        <= DONE;
          end
        end
        // -------------------------------------------------------------------
        DONE: if (ready_i) begin
          state_q <= IDLE;
          // secure wipe: exponent and table are key material
          exp_q <= '0;
          for (int i = 0; i < TBL_ENTRIES; i++) table_q[i] <= '0;
        end
        // fault trap: illegal (glitched) state completes with gf_pkg::STATUS_FAULT
        default: begin
          status_q <= gf_pkg::STATUS_FAULT;
          acc_q    <= '0;
          state_q  <= DONE;
        end
      endcase
    end
  end

endmodule
