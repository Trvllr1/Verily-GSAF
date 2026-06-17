// =============================================================================
// gf_microcode_rom - Opcode decode / dispatch policy ROM
// Copyright (c) 2026 Verily. All rights reserved.
//
// Maps opcode -> {legal, engine_class}. Future engines (ECC, Ed25519, X25519,
// RSA-CRT, PQC) extend this ROM only; scheduler architecture is unchanged.
// =============================================================================
`include "gf_pkg.sv"

module gf_microcode_rom
  import gf_pkg::*;
(
  input  gf_opcode_e opcode_i,
  output logic       legal_o,
  output logic [1:0] engine_class_o   // 0 = modexp, 1 = modinv
);

  always_comb begin
    legal_o        = 1'b0;
    engine_class_o = 2'd0;
    unique case (opcode_i)
      OP_MODEXP: begin legal_o = 1'b1; engine_class_o = 2'd0; end
      OP_MODINV: begin legal_o = 1'b1; engine_class_o = 2'd1; end
      // PQC engine: forward/inverse NTT and base multiplication
      OP_PQC:         begin legal_o = 1'b1; engine_class_o = 2'd2; end
      OP_PQC_FWD_NTT: begin legal_o = 1'b1; engine_class_o = 2'd2; end
      OP_PQC_INV_NTT: begin legal_o = 1'b1; engine_class_o = 2'd2; end
      // RSA-CRT engine: Bellcore-attack hardened RSA private key operation
      OP_RSA_CRT: begin legal_o = 1'b1; engine_class_o = 2'd3; end
      // OP_ECC_PADD/PDBL, OP_ED25519, OP_X25519:
      // reserved slots -> STATUS_UNSUPPORTED until engines land
      default: ;
    endcase
  end

endmodule
