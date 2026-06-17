// =============================================================================
// gf_operand_banks - Banked operand storage (NO single shared SRAM)
// Copyright (c) 2026 Verily. All rights reserved.
//
// NUM_OPERAND_BANKS independent banks. Each bank holds one transaction's
// operand set {A, B, M} plus its RESULT slot.
//
// CONTENTION-FREEDOM BY CONSTRUCTION (closes spec gap #4):
//   A bank is statically owned by exactly one transaction for its entire
//   lifetime. The host writes a bank only while it is FREE; exactly one
//   engine reads it while RUNNING; completion logic writes RESULT once.
//   Therefore no two requestors ever target the same bank in the same
//   cycle => zero port conflicts, zero arbitration, zero timing leakage.
//
// Secure wipe: bank contents are cleared on retire and on reset (operands
// may be key material).
// =============================================================================
`include "gf_pkg.sv"

module gf_operand_banks
  import gf_pkg::*;
#(
  parameter int unsigned WIDTH          = gf_pkg::GF_WIDTH_DEFAULT,
  parameter int unsigned EXP_BLIND_BITS = 64,
  // operand B (exponent) region is wider to hold blinded exponents
  localparam int unsigned EXP_W  = WIDTH + EXP_BLIND_BITS,
  localparam int unsigned WORDS  = (WIDTH + 31) / 32,
  localparam int unsigned BWORDS = (EXP_W + 31) / 32,
  localparam int unsigned WIDX_W = $clog2(BWORDS)
) (
  input  logic                       clk_i,
  input  logic                       rst_ni,

  // host word-write port (32-bit, from AXI frontend); bank must be FREE
  input  logic                       hw_we_i,
  input  logic [SEQ_W-1:0]           hw_bank_i,
  input  logic [1:0]                 hw_region_i,   // 0=A 1=B 2=M
  input  logic [WIDX_W-1:0]          hw_word_i,
  input  logic [31:0]                hw_data_i,

  // host word-read port (result readback)
  input  logic [SEQ_W-1:0]           hr_bank_i,
  input  logic [WIDX_W-1:0]          hr_word_i,
  output logic [31:0]                hr_data_o,

  // engine wide-read port (owned bank only; mux is static per transaction)
  input  logic [SEQ_W-1:0]           rd_bank_i,
  output logic [WIDTH-1:0]           rd_a_o,
  output logic [EXP_W-1:0]           rd_b_o,
  output logic [WIDTH-1:0]           rd_m_o,

  // completion wide-write port (result)
  input  logic                       res_we_i,
  input  logic [SEQ_W-1:0]           res_bank_i,
  input  logic [WIDTH-1:0]           res_data_i,

  // retire (secure wipe)
  input  logic                       wipe_i,
  input  logic [SEQ_W-1:0]           wipe_bank_i
);

  logic [WIDTH-1:0] bank_a [NUM_OPERAND_BANKS];
  logic [EXP_W-1:0] bank_b [NUM_OPERAND_BANKS];
  logic [WIDTH-1:0] bank_m [NUM_OPERAND_BANKS];
  logic [WIDTH-1:0] bank_r [NUM_OPERAND_BANKS];

  assign rd_a_o = bank_a[rd_bank_i];
  assign rd_b_o = bank_b[rd_bank_i];
  assign rd_m_o = bank_m[rd_bank_i];

  // host result readback (word-sliced; out-of-range words read 0)
  logic [WIDTH-1:0] hr_wide;
  assign hr_wide   = bank_r[hr_bank_i] >> ({{(WIDTH-WIDX_W){1'b0}}, hr_word_i} << 5);
  assign hr_data_o = hr_wide[31:0];

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      for (int b = 0; b < NUM_OPERAND_BANKS; b++) begin
        bank_a[b] <= '0; bank_b[b] <= '0; bank_m[b] <= '0; bank_r[b] <= '0;
      end
    end else begin
      if (hw_we_i) begin
        unique case (hw_region_i)
          // A and M are WIDTH wide: out-of-range word indices are dropped
          2'd0: if (32'(hw_word_i) < WORDS)
                  bank_a[hw_bank_i][hw_word_i*32 +: 32] <= hw_data_i;
          2'd1: bank_b[hw_bank_i][hw_word_i*32 +: 32] <= hw_data_i;
          2'd2: if (32'(hw_word_i) < WORDS)
                  bank_m[hw_bank_i][hw_word_i*32 +: 32] <= hw_data_i;
          default: ;
        endcase
      end
      if (res_we_i) bank_r[res_bank_i] <= res_data_i;
      if (wipe_i) begin
        bank_a[wipe_bank_i] <= '0;
        bank_b[wipe_bank_i] <= '0;
        bank_m[wipe_bank_i] <= '0;
        bank_r[wipe_bank_i] <= '0;
      end
    end
  end

endmodule
