// =============================================================================
// gf_pqc_engine - NTT butterfly engine for ML-KEM / ML-DSA
// Copyright (c) 2026 Verily. All rights reserved.
//
// Implements Number-Theoretic Transform (NTT) for post-quantum cryptography:
//   - ML-DSA (FIPS 204, Dilithium): complete 8-layer NTT, q = 8380417
//
// Architecture: NTT butterfly = modular multiply-accumulate, the same resource
// class as Montgomery multiplier lane. Uses reserved cluster lane via
// gf_engine_if interface.
//
// CONSTANT-TIME CONTRACT:
//   All NTT layers have fixed iteration counts. No data-dependent branches.
//   Forward NTT: 8 layers x 128 butterflies = 1024 butterfly operations.
//   Each butterfly: 1 modular multiply + 1 add + 1 sub (via reserved lane).
//
// Twiddle factors: precomputed ROM, 256 entries of zeta^bitrev(i,8) mod q.
// =============================================================================
`include "gf_pkg.sv"

module gf_pqc_engine
  import gf_pkg::*;
#(
  parameter int unsigned WIDTH = 23,
  parameter int unsigned N     = 256,
  parameter int unsigned Q     = 8380417,
  localparam int unsigned LG_N = $clog2(N)
) (
  input  logic               clk_i,
  input  logic               rst_ni,

  input  logic               valid_i,
  output logic               ready_o,
  input  logic [3:0]         opcode_i,
  input  logic [WIDTH-1:0]   base_i,
  input  logic [WIDTH-1:0]   m_i,

  output logic               valid_o,
  input  logic               ready_i,
  output logic [WIDTH-1:0]   result_o,
  output gf_status_e         status_o,

  output logic               mul_req_valid_o,
  input  logic               mul_req_ready_i,
  output logic [WIDTH-1:0]   mul_a_o,
  output logic [WIDTH-1:0]   mul_b_o,
  output logic [WIDTH-1:0]   mul_m_o,
  input  logic               mul_rsp_valid_i,
  output logic               mul_rsp_ready_o,
  input  logic [WIDTH-1:0]   mul_p_i,

  output logic               idle_o,

  output logic               coeff_wr_en,
  output logic [LG_N-1:0]    coeff_wr_addr,
  output logic [WIDTH-1:0]   coeff_wr_data,
  output logic               coeff_rd_en,
  output logic [LG_N-1:0]    coeff_rd_addr,
  input  logic [WIDTH-1:0]   coeff_rd_data
);

  // ─── State machine ───────────────────────────────────────────────────────
  typedef enum logic [3:0] {
    S_IDLE,
    S_READ_U,         // Read upper coefficient of butterfly pair
    S_READ_V,         // Read lower coefficient of butterfly pair
    S_MUL_ISSUE,      // Issue twiddle multiply
    S_MUL_WAIT,       // Wait for multiplier response
    S_COMBINE,        // Compute U+V and store both results
    S_DONE
  } state_e;
  state_e state_q;

  // ─── NTT control registers ──────────────────────────────────────────────
  logic [LG_N-1:0]   idx_q;          // current butterfly index (within layer)
  logic [LG_N-1:0]   t_q;            // butterfly span
  logic [3:0]        layer_q;        // current NTT layer (0..7)
  logic               fwd_mode_q;     // 1 = forward NTT

  // ─── Butterfly operands ─────────────────────────────────────────────────
  logic [WIDTH-1:0]  u_q, v_q;       // butterfly inputs (U, V)
  logic [WIDTH-1:0]  coeff_a_q;      // read coefficient A
  logic [WIDTH-1:0]  twiddle_q;      // twiddle factor for current butterfly
  logic [WIDTH-1:0]  mod_q;          // modulus register

  // ─── Twiddle factor ROM (ML-DSA: zeta=1753, q=8380417) ──────────────────
  logic [WIDTH-1:0] twiddle_rom [0:N-1];

  // Initialize ROM with precomputed twiddle factors
  // psis[i] = zeta^bitrev(i, 8) mod q
  initial begin
    twiddle_rom[0]   =        1; twiddle_rom[1]   =  4808194;
    twiddle_rom[2]   =  3765607; twiddle_rom[3]   =  3761513;
    twiddle_rom[4]   =  5178923; twiddle_rom[5]   =  5496691;
    twiddle_rom[6]   =  5234739; twiddle_rom[7]   =  5178987;
    twiddle_rom[8]   =  7778734; twiddle_rom[9]   =  3542485;
    twiddle_rom[10]  =  2682288; twiddle_rom[11]  =  2129892;
    twiddle_rom[12]  =  3764867; twiddle_rom[13]  =  7375178;
    twiddle_rom[14]  =   557458; twiddle_rom[15]  =  7159240;
    twiddle_rom[16]  =  5010068; twiddle_rom[17]  =  4317364;
    twiddle_rom[18]  =  2663378; twiddle_rom[19]  =  6705802;
    twiddle_rom[20]  =  4855975; twiddle_rom[21]  =  7946292;
    twiddle_rom[22]  =   676590; twiddle_rom[23]  =  7044481;
    twiddle_rom[24]  =  5152541; twiddle_rom[25]  =  1714295;
    twiddle_rom[26]  =  2453983; twiddle_rom[27]  =  1460718;
    twiddle_rom[28]  =  7737789; twiddle_rom[29]  =  4795319;
    twiddle_rom[30]  =  2815639; twiddle_rom[31]  =  2283733;
    twiddle_rom[32]  =  3602218; twiddle_rom[33]  =  3182878;
    twiddle_rom[34]  =  2740543; twiddle_rom[35]  =  4793971;
    twiddle_rom[36]  =  5269599; twiddle_rom[37]  =  2101410;
    twiddle_rom[38]  =  3704823; twiddle_rom[39]  =  1159875;
    twiddle_rom[40]  =   394148; twiddle_rom[41]  =   928749;
    twiddle_rom[42]  =  1095468; twiddle_rom[43]  =  4874037;
    twiddle_rom[44]  =  2071829; twiddle_rom[45]  =  4361428;
    twiddle_rom[46]  =  3241972; twiddle_rom[47]  =  2156050;
    twiddle_rom[48]  =  3415069; twiddle_rom[49]  =  1759347;
    twiddle_rom[50]  =  7562881; twiddle_rom[51]  =  4805951;
    twiddle_rom[52]  =  3756790; twiddle_rom[53]  =  6444618;
    twiddle_rom[54]  =  6663429; twiddle_rom[55]  =  4430364;
    twiddle_rom[56]  =  5483103; twiddle_rom[57]  =  3192354;
    twiddle_rom[58]  =   556856; twiddle_rom[59]  =  3870317;
    twiddle_rom[60]  =  2917338; twiddle_rom[61]  =  1853806;
    twiddle_rom[62]  =  3345963; twiddle_rom[63]  =  1858416;
    twiddle_rom[64]  =  3073009; twiddle_rom[65]  =  1277625;
    twiddle_rom[66]  =  5744944; twiddle_rom[67]  =  3852015;
    twiddle_rom[68]  =  4183372; twiddle_rom[69]  =  5157610;
    twiddle_rom[70]  =  5258977; twiddle_rom[71]  =  8106357;
    twiddle_rom[72]  =  2508980; twiddle_rom[73]  =  2028118;
    twiddle_rom[74]  =  1937570; twiddle_rom[75]  =  4564692;
    twiddle_rom[76]  =  2811291; twiddle_rom[77]  =  5396636;
    twiddle_rom[78]  =  7270901; twiddle_rom[79]  =  4158088;
    twiddle_rom[80]  =  1528066; twiddle_rom[81]  =   482649;
    twiddle_rom[82]  =  1148858; twiddle_rom[83]  =  5418153;
    twiddle_rom[84]  =  7814814; twiddle_rom[85]  =   169688;
    twiddle_rom[86]  =  2462444; twiddle_rom[87]  =  5046034;
    twiddle_rom[88]  =  4213992; twiddle_rom[89]  =  4892034;
    twiddle_rom[90]  =  1987814; twiddle_rom[91]  =  5183169;
    twiddle_rom[92]  =  1736313; twiddle_rom[93]  =   235407;
    twiddle_rom[94]  =  5130263; twiddle_rom[95]  =  3258457;
    twiddle_rom[96]  =  5801164; twiddle_rom[97]  =  1787943;
    twiddle_rom[98]  =  5989328; twiddle_rom[99]  =  6125690;
    twiddle_rom[100] =  3482206; twiddle_rom[101] =  4197502;
    twiddle_rom[102] =  7080401; twiddle_rom[103] =  6018354;
    twiddle_rom[104] =  7062739; twiddle_rom[105] =  2461387;
    twiddle_rom[106] =  3035980; twiddle_rom[107] =   621164;
    twiddle_rom[108] =  3901472; twiddle_rom[109] =  7153756;
    twiddle_rom[110] =  2925816; twiddle_rom[111] =  3374250;
    twiddle_rom[112] =  1356448; twiddle_rom[113] =  5604662;
    twiddle_rom[114] =  2683270; twiddle_rom[115] =  5601629;
    twiddle_rom[116] =  4912752; twiddle_rom[117] =  2312838;
    twiddle_rom[118] =  7727142; twiddle_rom[119] =  7921254;
    twiddle_rom[120] =   348812; twiddle_rom[121] =  8052569;
    twiddle_rom[122] =  1011223; twiddle_rom[123] =  6026202;
    twiddle_rom[124] =  4561790; twiddle_rom[125] =  6458164;
    twiddle_rom[126] =  6143691; twiddle_rom[127] =  1744507;
    twiddle_rom[128] =     1753; twiddle_rom[129] =  6444997;
    twiddle_rom[130] =  5720892; twiddle_rom[131] =  6924527;
    twiddle_rom[132] =  2660408; twiddle_rom[133] =  6600190;
    twiddle_rom[134] =  8321269; twiddle_rom[135] =  2772600;
    twiddle_rom[136] =  1182243; twiddle_rom[137] =    87208;
    twiddle_rom[138] =   636927; twiddle_rom[139] =  4415111;
    twiddle_rom[140] =  4423672; twiddle_rom[141] =  6084020;
    twiddle_rom[142] =  5095502; twiddle_rom[143] =  4663471;
    twiddle_rom[144] =  8352605; twiddle_rom[145] =   822541;
    twiddle_rom[146] =  1009365; twiddle_rom[147] =  5926272;
    twiddle_rom[148] =  6400920; twiddle_rom[149] =  1596822;
    twiddle_rom[150] =  4423473; twiddle_rom[151] =  4620952;
    twiddle_rom[152] =  6695264; twiddle_rom[153] =  4969849;
    twiddle_rom[154] =  2678278; twiddle_rom[155] =  4611469;
    twiddle_rom[156] =  4829411; twiddle_rom[157] =   635956;
    twiddle_rom[158] =  8129971; twiddle_rom[159] =  5925040;
    twiddle_rom[160] =  4234153; twiddle_rom[161] =  6607829;
    twiddle_rom[162] =  2192938; twiddle_rom[163] =  6653329;
    twiddle_rom[164] =  2387513; twiddle_rom[165] =  4768667;
    twiddle_rom[166] =  8111961; twiddle_rom[167] =  5199961;
    twiddle_rom[168] =  3747250; twiddle_rom[169] =  2296099;
    twiddle_rom[170] =  1239911; twiddle_rom[171] =  4541938;
    twiddle_rom[172] =  3195676; twiddle_rom[173] =  2642980;
    twiddle_rom[174] =  1254190; twiddle_rom[175] =  8368000;
    twiddle_rom[176] =  2998219; twiddle_rom[177] =   141835;
    twiddle_rom[178] =  8291116; twiddle_rom[179] =  2513018;
    twiddle_rom[180] =  7025525; twiddle_rom[181] =   613238;
    twiddle_rom[182] =  7070156; twiddle_rom[183] =  6161950;
    twiddle_rom[184] =  7921677; twiddle_rom[185] =  6458423;
    twiddle_rom[186] =  4040196; twiddle_rom[187] =  4908348;
    twiddle_rom[188] =  2039144; twiddle_rom[189] =  6500539;
    twiddle_rom[190] =  7561656; twiddle_rom[191] =  6201452;
    twiddle_rom[192] =  6757063; twiddle_rom[193] =  2105286;
    twiddle_rom[194] =  6006015; twiddle_rom[195] =  6346610;
    twiddle_rom[196] =   586241; twiddle_rom[197] =  7200804;
    twiddle_rom[198] =   527981; twiddle_rom[199] =  5637006;
    twiddle_rom[200] =  6903432; twiddle_rom[201] =  1994046;
    twiddle_rom[202] =  2491325; twiddle_rom[203] =  6987258;
    twiddle_rom[204] =   507927; twiddle_rom[205] =  7192532;
    twiddle_rom[206] =  7655613; twiddle_rom[207] =  6545891;
    twiddle_rom[208] =  5346675; twiddle_rom[209] =  8041997;
    twiddle_rom[210] =  2647994; twiddle_rom[211] =  3009748;
    twiddle_rom[212] =  5767564; twiddle_rom[213] =  4148469;
    twiddle_rom[214] =   749577; twiddle_rom[215] =  4357667;
    twiddle_rom[216] =  3980599; twiddle_rom[217] =  2569011;
    twiddle_rom[218] =  6764887; twiddle_rom[219] =  1723229;
    twiddle_rom[220] =  1665318; twiddle_rom[221] =  2028038;
    twiddle_rom[222] =  1163598; twiddle_rom[223] =  5011144;
    twiddle_rom[224] =  3994671; twiddle_rom[225] =  8368538;
    twiddle_rom[226] =  7009900; twiddle_rom[227] =  3020393;
    twiddle_rom[228] =  3363542; twiddle_rom[229] =   214880;
    twiddle_rom[230] =   545376; twiddle_rom[231] =  7609976;
    twiddle_rom[232] =  3105558; twiddle_rom[233] =  7277073;
    twiddle_rom[234] =   508145; twiddle_rom[235] =  7826699;
    twiddle_rom[236] =   860144; twiddle_rom[237] =  3430436;
    twiddle_rom[238] =   140244; twiddle_rom[239] =  6866265;
    twiddle_rom[240] =  6195333; twiddle_rom[241] =  3123762;
    twiddle_rom[242] =  2358373; twiddle_rom[243] =  6187330;
    twiddle_rom[244] =  5365997; twiddle_rom[245] =  6663603;
    twiddle_rom[246] =  2926054; twiddle_rom[247] =  7987710;
    twiddle_rom[248] =  8077412; twiddle_rom[249] =  3531229;
    twiddle_rom[250] =  4405932; twiddle_rom[251] =  4606686;
    twiddle_rom[252] =  1900052; twiddle_rom[253] =  7598542;
    twiddle_rom[254] =  1054478; twiddle_rom[255] =  7648983;
  end

  // ─── Completion ─────────────────────────────────────────────────────────
  logic [1:0]        done_cnt_q;

  assign ready_o  = (state_q == S_IDLE);
  assign valid_o  = (state_q == S_DONE);
  assign idle_o   = (state_q == S_IDLE);
  assign status_o = STATUS_OK;
  assign mul_rsp_ready_o = 1'b1;

  // ─── Coefficient memory control ─────────────────────────────────────────
  assign coeff_rd_en = (state_q == S_READ_U) || (state_q == S_READ_V);

  // Twiddle factor ROM address: layer base + group index
  // For layer m (1,2,4,...,128): twiddle index = m + group_idx
  logic [LG_N-1:0] twiddle_addr;
  assign twiddle_addr = t_q + (idx_q >> 1);

  // ─── Main FSM ───────────────────────────────────────────────────────────
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q        <= S_IDLE;
      idx_q          <= '0;
      t_q            <= '0;
      layer_q        <= '0;
      fwd_mode_q     <= 1'b1;
      u_q            <= '0;
      v_q            <= '0;
      coeff_a_q      <= '0;
      twiddle_q      <= '0;
      mod_q          <= '0;
      done_cnt_q     <= '0;
      mul_req_valid_o <= 1'b0;
      mul_a_o        <= '0;
      mul_b_o        <= '0;
      mul_m_o        <= '0;
      coeff_wr_en    <= 1'b0;
      coeff_wr_addr  <= '0;
      coeff_wr_data  <= '0;
    end else begin
      coeff_wr_en <= 1'b0;
      mul_req_valid_o <= 1'b0;

      unique case (state_q)
        // ---------------------------------------------------------------
        S_IDLE: begin
          if (valid_i) begin
            idx_q      <= '0;
            layer_q    <= '0;
            t_q        <= LG_N'(N/2);  // initial span = N/2
            fwd_mode_q <= (opcode_i == OP_PQC_FWD_NTT);
            mod_q      <= m_i;         // modulus
            state_q    <= S_READ_U;
          end
        end

        // ---------------------------------------------------------------
        S_READ_U: begin
          // Read coefficient at index idx_q (the "upper" element)
          coeff_rd_addr <= idx_q;
          state_q <= S_READ_V;
        end

        // ---------------------------------------------------------------
        S_READ_V: begin
          // Latch U, read V at idx_q + t
          coeff_a_q <= coeff_rd_data;  // U = A[j]
          coeff_rd_addr <= idx_q + t_q;
          twiddle_q <= twiddle_rom[twiddle_addr];
          state_q <= S_MUL_ISSUE;
        end

        // ---------------------------------------------------------------
        S_MUL_ISSUE: begin
          // V = A[j+t], issue twiddle multiply
          // Forward NTT (Cooley-Tukey): V' = V * twiddle
          // Inverse NTT (Gentleman-Sande): U' = U * twiddle (handled later)
          v_q <= coeff_rd_data;  // V = A[j+t]

          if (fwd_mode_q) begin
            // Forward: multiply V * twiddle
            mul_req_valid_o <= 1'b1;
            mul_a_o         <= coeff_rd_data;  // V
            mul_b_o         <= twiddle_q;
            mul_m_o         <= mod_q;
          end else begin
            // Inverse: multiply U * twiddle (for GS butterfly)
            mul_req_valid_o <= 1'b1;
            mul_a_o         <= coeff_a_q;  // U
            mul_b_o         <= twiddle_q;
            mul_m_o         <= mod_q;
          end

          state_q <= S_MUL_WAIT;
        end

        // ---------------------------------------------------------------
        S_MUL_WAIT: begin
          if (mul_rsp_valid_i) begin
            state_q <= S_COMBINE;
          end
        end

        // ---------------------------------------------------------------
        S_COMBINE: begin
          // Combine butterfly results and store
          if (fwd_mode_q) begin
            // Forward NTT (Cooley-Tukey):
            //   A[j]   = U + V*twiddle
            //   A[j+t] = U - V*twiddle
            coeff_wr_en   <= 1'b1;
            coeff_wr_addr <= idx_q;
            coeff_wr_data <= (coeff_a_q + mul_p_i) % mod_q;

            // Store A[j+t] on next cycle
            coeff_wr_en   <= 1'b1;
            coeff_wr_addr <= idx_q + t_q;
            coeff_wr_data <= (coeff_a_q + mod_q - mul_p_i) % mod_q;
          end else begin
            // Inverse NTT (Gentleman-Sande):
            //   A[j]   = U + V
            //   A[j+t] = (U - V) * twiddle
            coeff_wr_en   <= 1'b1;
            coeff_wr_addr <= idx_q;
            coeff_wr_data <= (coeff_a_q + v_q) % mod_q;

            coeff_wr_en   <= 1'b1;
            coeff_wr_addr <= idx_q + t_q;
            coeff_wr_data <= mul_p_i;  // (U - V) * twiddle already computed
          end

          // Advance to next butterfly
          idx_q <= idx_q + 1'b1;

          // Check if we've done all butterflies in this layer
          // Each butterfly pair processes 2 elements, so we iterate N/2 times
          if (idx_q == LG_N'(N/2 - 1)) begin
            // Layer complete
            layer_q <= layer_q + 1'b1;
            t_q     <= t_q >> 1;
            idx_q   <= '0;
            if (layer_q == 4'd7) begin
              state_q <= S_DONE;
            end else begin
              state_q <= S_READ_U;
            end
          end else begin
            state_q <= S_READ_U;
          end
        end

        // ---------------------------------------------------------------
        S_DONE: begin
          done_cnt_q <= done_cnt_q + 1'b1;
          if (done_cnt_q == 2'd2) begin
            state_q <= S_IDLE;
          end
        end

        default: state_q <= S_IDLE;
      endcase
    end
  end

  // ─── Result output ──────────────────────────────────────────────────────
  assign result_o = coeff_a_q;

endmodule
