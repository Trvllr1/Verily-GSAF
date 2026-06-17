// =============================================================================
// GreenField Secure Arithmetic Fabric (GSAF) - Common Package
// Copyright (c) 2026 Verily. All rights reserved.
//
// V5 architecture: constant-time, transaction-isolated cryptographic
// arithmetic fabric. See docs/ARCHITECTURE.md.
// =============================================================================
`ifndef GF_PKG_SV
`define GF_PKG_SV

package gf_pkg;

  // ---------------------------------------------------------------------------
  // Global parameters
  // ---------------------------------------------------------------------------
  // Operand width in bits. Production points: 2048/3072/4096 (RSA), 256/384 (ECC
  // field prep). Formal proofs run at 8/16. Simulation default kept small for
  // fast regression; override at elaboration.
  parameter int unsigned GF_WIDTH_DEFAULT = 64;

  // One operand bank per in-flight transaction: static ownership for the whole
  // transaction lifetime => zero port contention by construction.
  parameter int unsigned NUM_OPERAND_BANKS = 4;
  parameter int unsigned MAX_TXNS          = NUM_OPERAND_BANKS;

  parameter int unsigned TXN_ID_W = 8;   // host-supplied transaction tag
  parameter int unsigned SEQ_W    = $clog2(MAX_TXNS);

  // ---------------------------------------------------------------------------
  // Opcodes (microcode ROM maps opcode -> engine class; reserved slots for
  // future engines occupy the upper encodings without scheduler changes)
  // ---------------------------------------------------------------------------
  typedef enum logic [3:0] {
    OP_MODEXP      = 4'h0,
    OP_MODINV      = 4'h1,
    // -- reserved future engine slots (decode to STATUS_UNSUPPORTED today) --
    OP_ECC_PADD    = 4'h8,
    OP_ECC_PDBL    = 4'h9,
    OP_ED25519     = 4'hA,
    OP_X25519      = 4'hB,
    OP_RSA_CRT     = 4'hC,
    OP_PQC         = 4'hD
  } gf_opcode_e;

  // ---------------------------------------------------------------------------
  // Status codes
  // ---------------------------------------------------------------------------
  typedef enum logic [2:0] {
    STATUS_OK            = 3'd0,
    STATUS_INVALID_INPUT = 3'd1,  // modulus==0, modulus even, operand >= modulus
    STATUS_NOT_INVERTIBLE= 3'd2,  // gcd(a, m) != 1 for ModInv
    STATUS_UNSUPPORTED   = 3'd3,  // reserved opcode
    STATUS_FAULT         = 3'd7   // internal consistency check tripped
  } gf_status_e;

  // ---------------------------------------------------------------------------
  // Response ordering mode
  // ---------------------------------------------------------------------------
  typedef enum logic [0:0] {
    MODE_OOO      = 1'b0,
    MODE_IN_ORDER = 1'b1
  } gf_order_mode_e;

  // ---------------------------------------------------------------------------
  // Transaction lifecycle states (transaction_table)
  // ---------------------------------------------------------------------------
  typedef enum logic [2:0] {
    TXN_FREE     = 3'd0,
    TXN_LOADED   = 3'd1,  // operands resident in bank, command accepted
    TXN_RUNNING  = 3'd2,  // dispatched to an engine
    TXN_COMPLETE = 3'd3,  // completion record queued
    TXN_RETIRED  = 3'd4   // result consumed by host
  } gf_txn_state_e;

  // ---------------------------------------------------------------------------
  // Command / completion record types
  // ---------------------------------------------------------------------------
  typedef struct packed {
    logic [TXN_ID_W-1:0] txn_id;
    gf_opcode_e          opcode;
    logic [SEQ_W-1:0]    bank;     // operand bank ownership (== slot)
  } gf_cmd_t;

  typedef struct packed {
    logic [TXN_ID_W-1:0] txn_id;
    gf_opcode_e          opcode;
    gf_status_e          status;
    logic [SEQ_W-1:0]    bank;     // result pointer = owning bank
    logic [SEQ_W-1:0]    seq;      // dispatch sequence (reorder key)
  } gf_completion_t;

  // ---------------------------------------------------------------------------
  // Proof-derived divstep iteration bound (Bernstein-Yang 2019, safegcd).
  // For inputs of d bits:
  //   d <  46 : floor((49*d + 80) / 17)
  //   d >= 46 : floor((49*d + 57) / 17)
  // This is the published, machine-checked bound. Do NOT replace with 2*WIDTH.
  // ---------------------------------------------------------------------------
  function automatic int unsigned gf_divstep_bound(input int unsigned d);
    if (d < 46) return (49 * d + 80) / 17;
    else        return (49 * d + 57) / 17;
  endfunction

endpackage : gf_pkg

`endif // GF_PKG_SV
