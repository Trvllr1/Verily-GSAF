// =============================================================================
// tb_dyno_rsa_crt - Dyno test wrapper for gf_rsa_crt_engine
// Copyright (c) 2026 Verily. All rights reserved.
//
// Minimal test harness: instantiates the engine through gf_engine_if
// and a simulated multiplier lane. Used by cocotb dyno_rsa_crt.py tests.
// =============================================================================
`timescale 1ns/1ps
`include "gf_pkg.sv"

module tb_dyno_rsa_crt (
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

  // Multiplier lane signals (simulated)
  logic               mul_req_valid, mul_req_ready;
  logic [WIDTH-1:0]   mul_a, mul_b, mul_m, mul_p;
  logic               mul_rsp_valid, mul_rsp_ready;

  // RSA-CRT specific inputs (driven from cocotb)
  logic [WIDTH-1:0]   rsa_p, rsa_q, rsa_dp, rsa_dq, rsa_qinv;

  // Wrapper instantiation
  gf_rsa_crt_engine_wrapper #(
    .WIDTH (WIDTH),
    .EXP_W (WIDTH)
  ) u_wrapper (
    .clk_i          (clk_i),
    .rst_ni         (rst_ni),
    .engine_if      (engine_if),
    .rsa_p_i        (rsa_p),
    .rsa_q_i        (rsa_q),
    .rsa_dp_i       (rsa_dp),
    .rsa_dq_i       (rsa_dq),
    .rsa_qinv_i     (rsa_qinv),
    .mul_req_valid_o(mul_req_valid),
    .mul_req_ready_i(mul_req_ready),
    .mul_a_o        (mul_a),
    .mul_b_o        (mul_b),
    .mul_m_o        (mul_m),
    .mul_rsp_valid_i(mul_rsp_valid),
    .mul_rsp_ready_o(mul_rsp_ready),
    .mul_p_i        (mul_p)
  );

  // Simulated modular multiplier: (a * b) mod m
  function automatic logic [WIDTH-1:0] mulmod_fn(
    input logic [WIDTH-1:0] a_i, b_i, m_i
  );
    logic [2*WIDTH-1:0] product;
    logic [2*WIDTH-1:0] mod_m;
    logic [2*WIDTH-1:0] result;
    if (m_i == 0) return 0;
    mod_m = {{WIDTH{1'b0}}, m_i};
    product = {{WIDTH{1'b0}}, a_i} * {{WIDTH{1'b0}}, b_i};
    result = product % mod_m;
    return result[WIDTH-1:0];
  endfunction

  assign mul_req_ready = 1'b1;
  assign mul_p = mulmod_fn(mul_a, mul_b, mul_m);
  assign mul_rsp_valid = mul_req_valid;

  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb_dyno_rsa_crt);
  end

endmodule
