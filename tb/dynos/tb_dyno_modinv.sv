// =============================================================================
// tb_dyno_modinv - Dyno test wrapper for gf_modinv_engine
// Copyright (c) 2026 Verily. All rights reserved.
//
// Minimal test harness: instantiates the engine through gf_engine_if.
// Used by cocotb dyno_modinv.py tests.
// =============================================================================
`timescale 1ns/1ps
`include "gf_pkg.sv"

module tb_dyno_modinv;
  import gf_pkg::*;

  localparam int unsigned WIDTH = 64;

  logic clk = 0;
  logic rst_n = 0;
  always #5 clk = ~clk;

  // Engine interface
  gf_engine_if #(.WIDTH(WIDTH), .EXP_W(WIDTH)) engine_if (
    .clk_i  (clk),
    .rst_ni (rst_n)
  );

  // Wrapper instantiation
  gf_modinv_engine_wrapper #(
    .WIDTH         (WIDTH),
    .DIVSTEP_BOUND (gf_divstep_bound(WIDTH))
  ) u_wrapper (
    .clk_i     (clk),
    .rst_ni    (rst_n),
    .engine_if (engine_if)
  );

  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb_dyno_modinv);
  end

endmodule
