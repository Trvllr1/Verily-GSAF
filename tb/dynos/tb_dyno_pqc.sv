// =============================================================================
// tb_dyno_pqc - Dyno test wrapper for gf_pqc_engine
// Copyright (c) 2026 Verily. All rights reserved.
//
// Minimal test harness: instantiates the engine through gf_engine_if
// and a simulated multiplier lane. Used by cocotb dyno_pqc.py tests.
// =============================================================================
`timescale 1ns/1ps
`include "gf_pkg.sv"

module tb_dyno_pqc (
  input logic clk_i,
  input logic rst_ni
);
  import gf_pkg::*;

  localparam int unsigned WIDTH = 23;  // ML-DSA: ceil(log2(8380417))
  localparam int unsigned N     = 256;
  localparam int unsigned Q     = 8380417;

  // Engine interface
  gf_engine_if #(.WIDTH(WIDTH), .EXP_W(WIDTH)) engine_if (
    .clk_i  (clk_i),
    .rst_ni (rst_ni)
  );

  // Multiplier lane signals (simulated)
  logic               mul_req_valid, mul_req_ready;
  logic [WIDTH-1:0]   mul_a, mul_b, mul_m, mul_p;
  logic               mul_rsp_valid, mul_rsp_ready;

  // Coefficient memory signals
  logic               coeff_wr_en, coeff_rd_en;
  logic [$clog2(N)-1:0] coeff_wr_addr, coeff_rd_addr;
  logic [WIDTH-1:0]   coeff_wr_data, coeff_rd_data;

  // Simple coefficient memory (for simulation)
  logic [WIDTH-1:0] coeff_mem [0:N-1];

  always_ff @(posedge clk_i) begin
    if (coeff_wr_en)
      coeff_mem[coeff_wr_addr] <= coeff_wr_data;
  end

  assign coeff_rd_data = coeff_mem[coeff_rd_addr];

  // Wrapper instantiation
  gf_pqc_engine_wrapper #(
    .WIDTH (WIDTH),
    .N     (N),
    .Q     (Q)
  ) u_wrapper (
    .clk_i          (clk_i),
    .rst_ni         (rst_ni),
    .engine_if      (engine_if),
    .mul_req_valid_o(mul_req_valid),
    .mul_req_ready_i(mul_req_ready),
    .mul_a_o        (mul_a),
    .mul_b_o        (mul_b),
    .mul_m_o        (mul_m),
    .mul_rsp_valid_i(mul_rsp_valid),
    .mul_rsp_ready_o(mul_rsp_ready),
    .mul_p_i        (mul_p),
    .coeff_wr_en    (coeff_wr_en),
    .coeff_wr_addr  (coeff_wr_addr),
    .coeff_wr_data  (coeff_wr_data),
    .coeff_rd_en    (coeff_rd_en),
    .coeff_rd_addr  (coeff_rd_addr),
    .coeff_rd_data  (coeff_rd_data)
  );

  // Simulated Montgomery multiplier: a*b*R^-1 mod m, R = 2^WIDTH
  function automatic logic [WIDTH-1:0] mont_mult_fn(
    input logic [WIDTH-1:0] a, b, m
  );
    logic [WIDTH:0] acc;
    acc = '0;
    for (int i = 0; i < WIDTH; i++) begin
      if (a[i]) acc = acc + {1'b0, b};
      if (acc[0]) acc = acc + {1'b0, m};
      acc = acc >> 1;
    end
    if (acc >= {1'b0, m}) acc = acc - {1'b0, m};
    return acc[WIDTH-1:0];
  endfunction

  assign mul_req_ready = 1'b1;
  assign mul_p = mont_mult_fn(mul_a, mul_b, mul_m);
  assign mul_rsp_valid = mul_req_valid;

  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb_dyno_pqc);
  end

endmodule
