// =============================================================================
// tb_dyno_modexp - Dyno test wrapper for gf_modexp_engine
// Copyright (c) 2026 Verily. All rights reserved.
//
// Minimal test harness: instantiates the engine through gf_engine_if
// and a simulated multiplier lane. Used by cocotb dyno_modexp.py tests.
// =============================================================================
`timescale 1ns/1ps
`include "gf_pkg.sv"

module tb_dyno_modexp;
  import gf_pkg::*;

  localparam int unsigned WIDTH          = 64;
  localparam int unsigned EXP_BLIND_BITS = 64;
  localparam int unsigned EXP_W          = WIDTH + EXP_BLIND_BITS;

  logic clk = 0;
  logic rst_n = 0;
  always #5 clk = ~clk;

  // Engine interface
  gf_engine_if #(.WIDTH(WIDTH), .EXP_W(EXP_W)) engine_if (
    .clk_i  (clk),
    .rst_ni (rst_n)
  );

  // Multiplier lane signals (simulated — single-cycle response)
  logic               mul_req_valid, mul_req_ready;
  logic [WIDTH-1:0]   mul_a, mul_b, mul_m, mul_p;
  logic               mul_rsp_valid, mul_rsp_ready;

  // Wrapper instantiation
  gf_modexp_engine_wrapper #(
    .WIDTH          (WIDTH),
    .WINDOW_SIZE    (4),
    .EXP_BLIND_BITS (EXP_BLIND_BITS)
  ) u_wrapper (
    .clk_i          (clk),
    .rst_ni         (rst_n),
    .engine_if      (engine_if),
    .mul_req_valid_o(mul_req_valid),
    .mul_req_ready_i(mul_req_ready),
    .mul_a_o        (mul_a),
    .mul_b_o        (mul_b),
    .mul_m_o        (mul_m),
    .mul_rsp_valid_i(mul_rsp_valid),
    .mul_rsp_ready_o(mul_rsp_ready),
    .mul_p_i        (mul_p)
  );

  // Simulated multiplier: computes mont_mult(a, b, m) in single cycle
  // (for functional verification only — not cycle-accurate)
  assign mul_req_ready = 1'b1;
  always_ff @(posedge clk) begin
    if (mul_req_valid) begin
      // Simple Montgomery multiply approximation for functional check
      // Real verification uses the golden model in cocotb
      mul_p <= (mul_a * mul_b) % mul_m;
      mul_rsp_valid <= 1'b1;
    end else begin
      mul_rsp_valid <= 1'b0;
    end
  end

  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb_dyno_modexp);
  end

endmodule
