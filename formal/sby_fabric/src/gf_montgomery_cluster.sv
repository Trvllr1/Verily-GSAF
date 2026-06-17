// =============================================================================
// gf_mult_reservation_table + gf_montgomery_cluster
// Copyright (c) 2026 Verily. All rights reserved.
//
// Round-robin arbitration is FORBIDDEN (timing side channel). Instead each
// multiplier lane is statically reserved to one engine class at elaboration:
//
//     lane[k] <- engine[k]   for the engine's whole transaction lifetime
//
// Properties delivered:
//   - static lane reservation (compile-time map, not runtime arbitration)
//   - deterministic slot ownership (no mid-transaction stealing possible:
//     there is no datapath by which another engine can reach the lane)
//   - fixed request latency (pure wiring; zero arbitration cycles)
//
// MULT_LATENCY is derived (WIDTH+2), not a free parameter -- the draft spec's
// fixed "16" is only valid at one operating point.
// =============================================================================
`include "gf_pkg.sv"

module gf_montgomery_cluster #(
  parameter int unsigned WIDTH           = gf_pkg::GF_WIDTH_DEFAULT,
  parameter int unsigned NUM_MULTIPLIERS = 1   // 1..8 supported
) (
  input  logic             clk_i,
  input  logic             rst_ni,

  // one statically reserved lane per requestor
  input  logic             req_valid_i  [NUM_MULTIPLIERS],
  output logic             req_ready_o  [NUM_MULTIPLIERS],
  input  logic [WIDTH-1:0] req_a_i      [NUM_MULTIPLIERS],
  input  logic [WIDTH-1:0] req_b_i      [NUM_MULTIPLIERS],
  input  logic [WIDTH-1:0] req_m_i      [NUM_MULTIPLIERS],

  output logic             rsp_valid_o  [NUM_MULTIPLIERS],
  input  logic             rsp_ready_i  [NUM_MULTIPLIERS],
  output logic [WIDTH-1:0] rsp_p_o      [NUM_MULTIPLIERS],

  output logic             idle_o
);

  logic lane_idle [NUM_MULTIPLIERS];

  for (genvar k = 0; k < NUM_MULTIPLIERS; k++) begin : g_lane
    // reservation table entry k: engine k <-> multiplier k, hard-wired.
    gf_mont_mult #(.WIDTH(WIDTH)) u_mult (
      .clk_i,
      .rst_ni,
      .valid_i (req_valid_i[k]),
      .ready_o (req_ready_o[k]),
      .a_i     (req_a_i[k]),
      .b_i     (req_b_i[k]),
      .m_i     (req_m_i[k]),
      .valid_o (rsp_valid_o[k]),
      .ready_i (rsp_ready_i[k]),
      .p_o     (rsp_p_o[k]),
      .idle_o  (lane_idle[k])
    );
  end

  always_comb begin
    idle_o = 1'b1;
    for (int k = 0; k < NUM_MULTIPLIERS; k++) idle_o &= lane_idle[k];
  end

endmodule
