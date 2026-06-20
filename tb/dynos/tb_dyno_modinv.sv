// =============================================================================
// tb_dyno_modinv - Dyno test wrapper for gf_modinv_engine
// Copyright (c) 2026 Verily. All rights reserved.
//
// Minimal test harness: instantiates the engine through gf_engine_if.
// Used by cocotb dyno_modinv.py tests.
// =============================================================================
`timescale 1ns/1ps
`include "gf_pkg.sv"

module tb_dyno_modinv (
  input logic clk_i,
  input logic rst_ni
);
  import gf_pkg::*;

  localparam int unsigned WIDTH = 64;

  // Engine interface
  gf_engine_if #(.WIDTH(WIDTH), .EXP_W(WIDTH)) engine_if (
    .clk_i  (clk_i),
    .rst_ni (rst_ni)
  );

  // Wrapper instantiation (DIVSTEP_BOUND from gf_pkg pre-computed parameters)
  gf_modinv_engine_wrapper #(
    .WIDTH         (WIDTH),
    .DIVSTEP_BOUND (GF_DIVSTEP_BOUND_64)
  ) u_wrapper (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .engine_if (engine_if)
  );

  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb_dyno_modinv);
  end

endmodule
