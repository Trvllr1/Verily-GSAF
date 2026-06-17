// =============================================================================
// gf_mont_mult - Radix-2 bit-serial Montgomery multiplier
// Copyright (c) 2026 Verily. All rights reserved.
//
// result = a * b * R^-1 mod m, R = 2^WIDTH, m odd, a,b < m.
//
// CONSTANT-TIME CONTRACT:
//   Latency is exactly WIDTH + 2 cycles from handshake, for ALL inputs.
//   The final subtraction is computed unconditionally and selected by mux;
//   no data-dependent branches, no early exit, no '*', '/', '%'.
//
// Clock gating: no manual gates. `idle_o` exported for tool-inserted ICG.
// =============================================================================
`include "gf_pkg.sv"

module gf_mont_mult #(
  parameter int unsigned WIDTH = gf_pkg::GF_WIDTH_DEFAULT,
  // Derived, not free: latency scales with WIDTH (spec V5 erratum: the fixed
  // MULT_LATENCY=16 of the draft is only valid at one operating point).
  parameter int unsigned MULT_LATENCY = WIDTH + 2
) (
  input  logic               clk_i,
  input  logic               rst_ni,

  // request (valid/ready)
  input  logic               valid_i,
  output logic               ready_o,
  input  logic [WIDTH-1:0]   a_i,
  input  logic [WIDTH-1:0]   b_i,
  input  logic [WIDTH-1:0]   m_i,

  // response (valid/ready)
  output logic               valid_o,
  input  logic               ready_i,
  output logic [WIDTH-1:0]   p_o,

  output logic               idle_o
);

  typedef enum logic [1:0] {S_IDLE, S_RUN, S_REDUCE, S_DONE} state_e;
  state_e state_q, state_d;

  localparam int unsigned CNT_W = $clog2(WIDTH + 1);

  logic [WIDTH-1:0]  a_q, b_q, m_q;
  logic [WIDTH+1:0]  acc_q;            // acc < 2m fits in WIDTH+1; +1 headroom
  logic [CNT_W-1:0]  cnt_q;
  logic [WIDTH-1:0]  p_q;

  // one radix-2 step: acc' = (acc + a[i]&b + odd&m) >> 1
  logic [WIDTH+1:0] sum_ab;
  logic [WIDTH+1:0] sum_abm;
  logic             a_bit;

  assign a_bit   = a_q[0];
  assign sum_ab  = acc_q + ({(WIDTH+2){a_bit}} & {2'b00, b_q});
  assign sum_abm = sum_ab + ({(WIDTH+2){sum_ab[0]}} & {2'b00, m_q});

  // unconditional final subtract + mux (constant time)
  logic [WIDTH+1:0] acc_minus_m;
  assign acc_minus_m = acc_q - {2'b00, m_q};

  assign ready_o = (state_q == S_IDLE);
  assign valid_o = (state_q == S_DONE);
  assign p_o     = p_q;
  assign idle_o  = (state_q == S_IDLE);

  always_comb begin
    state_d = state_q;
    unique case (state_q)
      S_IDLE:   if (valid_i)               state_d = S_RUN;
      S_RUN:    if (cnt_q == CNT_W'(WIDTH-1)) state_d = S_REDUCE;
      S_REDUCE:                            state_d = S_DONE;
      S_DONE:   if (ready_i)               state_d = S_IDLE;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= S_IDLE;
      a_q     <= '0;
      b_q     <= '0;
      m_q     <= '0;
      acc_q   <= '0;
      cnt_q   <= '0;
      p_q     <= '0;
    end else begin
      state_q <= state_d;
      unique case (state_q)
        S_IDLE: if (valid_i) begin
          a_q   <= a_i;
          b_q   <= b_i;
          m_q   <= m_i;
          acc_q <= '0;
          cnt_q <= '0;
        end
        S_RUN: begin
          acc_q <= sum_abm >> 1;
          a_q   <= a_q >> 1;        // consume next bit; operand a wiped as used
          cnt_q <= cnt_q + 1'b1;
        end
        S_REDUCE: begin
          // select subtracted value iff acc >= m (borrow-free), mux not branch
          p_q   <= acc_minus_m[WIDTH+1] ? acc_q[WIDTH-1:0]
                                        : acc_minus_m[WIDTH-1:0];
        end
        S_DONE: if (ready_i) begin
          // secure wipe of residual operand state on retirement
          a_q   <= '0;
          b_q   <= '0;
          acc_q <= '0;
        end
      endcase
    end
  end

`ifdef GF_ASSERTIONS
  // latency invariance: DONE is reached exactly WIDTH+1 cycles after accept
  logic [CNT_W:0] lat_q;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)                      lat_q <= '0;
    else if (state_q==S_IDLE && valid_i) lat_q <= '0;
    else if (state_q != S_IDLE && state_q != S_DONE) lat_q <= lat_q + 1'b1;
  end
  a_const_latency: assert property (@(posedge clk_i) disable iff (!rst_ni)
    (state_q==S_REDUCE && state_d==S_DONE) |-> lat_q == (CNT_W+1)'(WIDTH));
`endif

endmodule
