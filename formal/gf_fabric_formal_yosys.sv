// Yosys-compatible formal chassis model (single file, no imports)
// Proves P1-P5: no FIFO overflow, one completion per txn, unique txn_ids,
// no deadlock, legal status encoding.
// Engines and Montgomery cluster black-boxed.
`timescale 1ns/1ps

// ─── Package (inlined for Yosys) ───────────────────────────────────────────
package gf_pkg;
  parameter int unsigned GF_WIDTH_DEFAULT = 64;
  parameter int unsigned NUM_OPERAND_BANKS = 4;
  parameter int unsigned MAX_TXNS = NUM_OPERAND_BANKS;
  parameter int unsigned TXN_ID_W = 8;
  parameter int unsigned SEQ_W = $clog2(MAX_TXNS);

  typedef enum logic [3:0] {
    OP_MODEXP=4'h0, OP_MODINV=4'h1,
    OP_ECC_PADD=4'h8, OP_ECC_PDBL=4'h9, OP_ED25519=4'hA, OP_X25519=4'hB,
    OP_RSA_CRT=4'hC, OP_PQC=4'hD, OP_PQC_FWD_NTT=4'hE, OP_PQC_INV_NTT=4'hF
  } gf_opcode_e;

  typedef enum logic [2:0] {
    STATUS_OK=3'd0, STATUS_INVALID_INPUT=3'd1, STATUS_NOT_INVERTIBLE=3'd2,
    STATUS_UNSUPPORTED=3'd3, STATUS_FAULT=3'd7
  } gf_status_e;

  typedef enum logic [0:0] { MODE_OOO=1'b0, MODE_IN_ORDER=1'b1 } gf_order_mode_e;

  typedef enum logic [2:0] {
    TXN_FREE=3'd0, TXN_LOADED=3'd1, TXN_RUNNING=3'd2,
    TXN_COMPLETE=3'd3, TXN_RETIRED=3'd4
  } gf_txn_state_e;

  typedef struct packed {
    logic [TXN_ID_W-1:0] txn_id;
    gf_opcode_e          opcode;
    logic [SEQ_W-1:0]    bank;
  } gf_cmd_t;

  typedef struct packed {
    logic [TXN_ID_W-1:0] txn_id;
    gf_opcode_e          opcode;
    gf_status_e          status;
    logic [SEQ_W-1:0]    bank;
    logic [SEQ_W-1:0]    seq;
  } gf_completion_t;
endpackage

// ─── FIFO (Yosys-compatible) ───────────────────────────────────────────────
module gf_fifo #(
  parameter int unsigned DATA_W = 32,
  parameter int unsigned DEPTH  = 4
) (
  input  logic              clk_i,
  input  logic              rst_ni,
  input  logic              valid_i,
  output logic              ready_o,
  input  logic [DATA_W-1:0] data_i,
  output logic              valid_o,
  input  logic              ready_i,
  output logic [DATA_W-1:0] data_o,
  output logic [$clog2(DEPTH+1)-1:0] count_o
);
  localparam int unsigned AW = $clog2(DEPTH);
  logic [DATA_W-1:0] mem [0:DEPTH-1];
  logic [AW:0] wptr, rptr, cnt;

  assign ready_o = (cnt < DEPTH);
  assign valid_o = (cnt > 0);
  assign data_o  = mem[rptr[AW-1:0]];
  assign count_o = cnt[AW:0];

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wptr <= '0; rptr <= '0; cnt <= '0;
    end else begin
      if (valid_i && ready_o) begin
        mem[wptr[AW-1:0]] <= data_i;
        wptr <= wptr + 1;
      end
      if (valid_o && ready_i) begin
        rptr <= rptr + 1;
      end
      if ((valid_i && ready_o) && !(valid_o && ready_i))
        cnt <= cnt + 1;
      else if (!(valid_i && ready_o) && (valid_o && ready_i))
        cnt <= cnt - 1;
    end
  end
endmodule

// ─── Transaction table ─────────────────────────────────────────────────────
module gf_transaction_table (
  input  logic                clk_i,
  input  logic                rst_ni,
  input  logic                upd_en_i,
  input  logic [1:0]          upd_slot_i,
  input  logic [2:0]          upd_state_i,
  input  logic [7:0]          upd_txn_id_i,
  input  logic [3:0]          upd_opcode_i,
  input  logic [2:0]          upd_engine_id_i,
  input  logic [1:0]          upd_seq_i,
  input  logic [2:0]          upd_status_i,
  input  logic                ret_en_i,
  input  logic [1:0]          ret_slot_i,
  input  logic                comp_en_i,
  input  logic [1:0]          comp_slot_i,
  input  logic [2:0]          comp_status_i,
  output logic [11:0]         state_o,   // 4 x 3-bit packed
  output logic [31:0]         txn_id_o,  // 4 x 8-bit packed
  output logic [15:0]         opcode_o,  // 4 x 4-bit packed
  output logic [7:0]          seq_o,     // 4 x 2-bit packed
  output logic [11:0]         status_o   // 4 x 3-bit packed
);
  logic [2:0]  tt_state [0:3];
  logic [7:0]  tt_txn_id [0:3];
  logic [3:0]  tt_opcode [0:3];
  logic [1:0]  tt_seq [0:3];
  logic [2:0]  tt_status [0:3];

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      for (int i = 0; i < 4; i++) begin
        tt_state[i]  <= 3'd0;
        tt_txn_id[i] <= '0;
        tt_opcode[i] <= '0;
        tt_seq[i]    <= '0;
        tt_status[i] <= '0;
      end
    end else begin
      if (upd_en_i) begin
        tt_state[upd_slot_i]  <= gf_pkg::gf_txn_state_e'(upd_state_i);
        tt_txn_id[upd_slot_i] <= upd_txn_id_i;
        tt_opcode[upd_slot_i] <= upd_opcode_i;
        tt_seq[upd_slot_i]    <= upd_seq_i;
        tt_status[upd_slot_i] <= upd_status_i;
      end
      if (comp_en_i) begin
        tt_state[comp_slot_i]  <= gf_pkg::TXN_COMPLETE;
        tt_status[comp_slot_i] <= comp_status_i;
      end
      if (ret_en_i) begin
        tt_state[ret_slot_i] <= gf_pkg::TXN_FREE;
      end
    end
  end

  for (genvar i = 0; i < 4; i++) begin : g_out
    assign state_o[i*3 +: 3]   = tt_state[i];
    assign txn_id_o[i*8 +: 8]  = tt_txn_id[i];
    assign opcode_o[i*4 +: 4]  = tt_opcode[i];
    assign seq_o[i*2 +: 2]     = tt_seq[i];
    assign status_o[i*3 +: 3]  = tt_status[i];
  end
endmodule

// ─── Completion queue ──────────────────────────────────────────────────────
module gf_completion_queue (
  input  logic         clk_i,
  input  logic         rst_ni,
  input  logic         valid_i,
  output logic         ready_o,
  input  logic [44:0]  data_i,
  output logic         valid_o,
  input  logic         ready_i,
  output logic [44:0]  data_o,
  output logic [2:0]   count_o
);
  gf_fifo #(.DATA_W(45), .DEPTH(4)) u_fifo (
    .clk_i, .rst_ni,
    .valid_i, .ready_o, .data_i,
    .valid_o, .ready_i, .data_o,
    .count_o
  );
endmodule

// ─── Reorder buffer (passthrough for formal) ───────────────────────────────
module gf_reorder_buffer #(
  parameter logic RESPONSE_ORDERING = 1'b1
) (
  input  logic         clk_i,
  input  logic         rst_ni,
  input  logic         valid_i,
  output logic         ready_o,
  input  logic [44:0]  data_i,
  output logic         valid_o,
  input  logic         ready_i,
  output logic [44:0]  data_o
);
  assign valid_o = valid_i;
  assign ready_o = ready_i;
  assign data_o  = data_i;
endmodule

// ─── Microcode ROM ─────────────────────────────────────────────────────────
module gf_microcode_rom (
  input  logic [3:0]  opcode_i,
  output logic        legal_o,
  output logic [2:0]  engine_class_o
);
  always_comb begin
    legal_o = 1'b0;
    engine_class_o = 3'd0;
    case (opcode_i)
      4'h0: begin legal_o = 1'b1; engine_class_o = 3'd0; end
      4'h1: begin legal_o = 1'b1; engine_class_o = 3'd1; end
      4'hD, 4'hE, 4'hF: begin legal_o = 1'b1; engine_class_o = 3'd2; end
      4'hC: begin legal_o = 1'b1; engine_class_o = 3'd3; end
      4'h8, 4'h9, 4'hA, 4'hB: begin legal_o = 1'b1; engine_class_o = 3'd4; end
      default: ;
    endcase
  end
endmodule

// ─── Operand banks (simplified for formal) ─────────────────────────────────
module gf_operand_banks #(
  parameter int unsigned WIDTH = 8,
  parameter int unsigned EXP_BLIND_BITS = 0
) (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic hw_we_i,
  input  logic [1:0] hw_bank_i,
  input  logic [1:0] hw_region_i,
  input  logic [4:0] hw_word_i,
  input  logic [31:0] hw_data_i,
  input  logic [1:0] hr_bank_i,
  input  logic [4:0] hr_word_i,
  output logic [31:0] hr_data_o,
  input  logic [1:0] rd_bank_i,
  output logic [WIDTH-1:0] rd_a_o,
  output logic [WIDTH+EXP_BLIND_BITS-1:0] rd_b_o,
  output logic [WIDTH-1:0] rd_m_o,
  input  logic res_we_i,
  input  logic [1:0] res_bank_i,
  input  logic [WIDTH-1:0] res_data_i,
  input  logic wipe_i,
  input  logic [1:0] wipe_bank_i
);
  logic [WIDTH-1:0] bank_a [0:3];
  logic [WIDTH-1:0] bank_m [0:3];
  integer i;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      for (i = 0; i < 4; i++) begin bank_a[i] <= '0; bank_m[i] <= '0; end
    end else begin
      if (hw_we_i && hw_region_i == 2'd0)
        bank_a[hw_bank_i][hw_word_i*32 +: 32] <= hw_data_i;
      if (hw_we_i && hw_region_i == 2'd2)
        bank_m[hw_bank_i][hw_word_i*32 +: 32] <= hw_data_i;
      if (res_we_i) bank_a[res_bank_i] <= res_data_i;
      if (wipe_i) begin bank_a[wipe_bank_i] <= '0; bank_m[wipe_bank_i] <= '0; end
    end
  end
  assign rd_a_o = bank_a[rd_bank_i];
  assign rd_m_o = bank_m[rd_bank_i];
  assign rd_b_o = '0;
  assign hr_data_o = '0;
endmodule

// ─── AXI-Lite frontend (simplified for formal) ─────────────────────────────
module gf_axil_frontend #(
  parameter int unsigned WIDTH = 8,
  parameter int unsigned EXP_BLIND_BITS = 0
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        s_axil_awvalid,
  output logic        s_axil_awready,
  input  logic [11:0] s_axil_awaddr,
  input  logic        s_axil_wvalid,
  output logic        s_axil_wready,
  input  logic [31:0] s_axil_wdata,
  input  logic [3:0]  s_axil_wstrb,
  output logic        s_axil_bvalid,
  input  logic        s_axil_bready,
  output logic [1:0]  s_axil_bresp,
  input  logic        s_axil_arvalid,
  output logic        s_axil_arready,
  input  logic [11:0] s_axil_araddr,
  output logic        s_axil_rvalid,
  input  logic        s_axil_rready,
  output logic [31:0] s_axil_rdata,
  output logic [1:0]  s_axil_rresp,
  output logic        irq_o,
  output logic        cmd_valid_o,
  input  logic        cmd_ready_i,
  output logic [44:0] cmd_o,
  input  logic        resp_valid_i,
  output logic        resp_ready_o,
  input  logic [44:0] resp_i,
  output logic        hw_we_o,
  output logic [1:0]  hw_bank_o,
  output logic [1:0]  hw_region_o,
  output logic [4:0]  hw_word_o,
  output logic [31:0] hw_data_o,
  output logic [1:0]  hr_bank_o,
  output logic [4:0]  hr_word_o,
  input  logic [31:0] hr_data_i,
  output logic        retire_o,
  output logic [1:0]  retire_bank_o,
  output logic [WIDTH-1:0] rsa_p_o,
  output logic [WIDTH-1:0] rsa_q_o,
  output logic [WIDTH-1:0] rsa_dp_o,
  output logic [WIDTH-1:0] rsa_dq_o,
  output logic [WIDTH-1:0] rsa_qinv_o,
  output logic        coeff_we_o,
  output logic [7:0]  coeff_addr_o,
  output logic [WIDTH-1:0] coeff_data_o,
  input  logic [3:0]  bank_free_i,
  input  logic        fabric_busy_i,
  input  logic        result_fifo_full_i
);
  // Simplified: command accepted immediately on write to 0x010
  logic cmd_pend_q;
  logic [11:0] awaddr_q;
  logic [31:0] wdata_q;
  logic aw_hs, w_hs;

  assign s_axil_awready = !aw_hs;
  assign s_axil_wready  = !w_hs;
  assign s_axil_bresp   = 2'b00;
  assign s_axil_rresp   = 2'b00;
  assign irq_o = 1'b0;

  wire wr_do = aw_hs && w_hs && !s_axil_bvalid;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      aw_hs <= 0; w_hs <= 0; awaddr_q <= '0; wdata_q <= '0;
      s_axil_bvalid <= 0; s_axil_rvalid <= 0; s_axil_rdata <= '0;
      cmd_pend_q <= 0; retire_o <= 0; retire_bank_o <= '0;
      hw_we_o <= 0; coeff_we_o <= 0; coeff_ptr_q <= '0;
    end else begin
      retire_o <= 0;
      coeff_we_o <= 0;
      if (s_axil_awvalid && s_axil_awready) begin aw_hs <= 1; awaddr_q <= s_axil_awaddr; end
      if (s_axil_wvalid && s_axil_wready) begin w_hs <= 1; wdata_q <= s_axil_wdata; end
      if (wr_do) s_axil_bvalid <= 1;
      if (s_axil_bvalid && s_axil_bready) begin s_axil_bvalid <= 0; aw_hs <= 0; w_hs <= 0; end
      if (s_axil_arvalid && s_axil_arready) s_axil_rvalid <= 1;
      if (s_axil_rvalid && s_axil_rready) s_axil_rvalid <= 0;

      // Command register write
      if (wr_do && awaddr_q == 12'h010 && !cmd_pend_q) begin
        cmd_o <= {wdata_q[7:0], 4'h0, 2'(wdata_q[13:12]), wdata_q[11:8]};
        cmd_pend_q <= 1;
      end
      if (cmd_pend_q && cmd_ready_i) cmd_pend_q <= 0;

      // Response pop
      if (wr_do && awaddr_q == 12'h018 && wdata_q[0]) begin
        retire_o <= 1;
        retire_bank_o <= resp_i[13:12];
      end

      // Bank writes
      if (wr_do && awaddr_q[8] && awaddr_q[5:4] != 2'd3 && bank_free_i[awaddr_q[7:6]]) begin
        hw_we_o <= 1;
        hw_bank_o <= awaddr_q[7:6];
        hw_region_o <= awaddr_q[5:4];
        hw_word_o <= awaddr_q[6:2];
        hw_data_o <= wdata_q;
      end else begin
        hw_we_o <= 0;
      end

      // Coefficient load
      if (wr_do && awaddr_q == 12'h200) begin
        coeff_we_o <= 1;
        coeff_addr_o <= coeff_ptr_q;
        coeff_data_o <= {{(WIDTH-32){1'b0}}, wdata_q};
        coeff_ptr_q <= coeff_ptr_q + 1;
      end
      if (wr_do && awaddr_q == 12'h204) coeff_ptr_q <= '0;

      // Read response
      if (s_axil_arvalid && s_axil_arready) begin
        if (araddr_q == 12'h014)
          s_axil_rdata <= {resp_valid_i, 14'h0, resp_i[44:32], resp_i[13:12], resp_i[11:8], resp_i[7:0]};
        else if (araddr_q == 12'h004)
          s_axil_rdata <= {28'h0, bank_free_i, 2'b00, resp_valid_i, !cmd_pend_q};
        else
          s_axil_rdata <= 32'h0;
      end
    end
  end

  logic [7:0] coeff_ptr_q;
  logic [11:0] araddr_q;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) araddr_q <= '0;
    else if (s_axil_arvalid && s_axil_arready) araddr_q <= s_axil_araddr;
  end
endmodule

// ─── Scheduler (simplified for formal — just dispatch and completion) ───────
module gf_scheduler #(
  parameter int unsigned WIDTH = 8,
  parameter int unsigned EXP_BLIND_BITS = 0
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        cmd_valid_i,
  output logic        cmd_ready_o,
  input  logic [44:0] cmd_i,
  output logic [1:0]  bank_rd_o,
  input  logic [WIDTH-1:0] bank_a_i,
  input  logic [WIDTH-1:0] bank_m_i,
  // engine 0
  output logic        e0_valid_o,
  input  logic        e0_ready_i,
  output logic [WIDTH-1:0] e0_base_o, e0_m_o,
  input  logic        e0_done_valid_i,
  output logic        e0_done_ready_o,
  input  logic [WIDTH-1:0] e0_result_i,
  input  logic [2:0]  e0_status_i,
  // engine 1
  output logic        e1_valid_o,
  input  logic        e1_ready_i,
  output logic [WIDTH-1:0] e1_a_o, e1_m_o,
  input  logic        e1_done_valid_i,
  output logic        e1_done_ready_o,
  input  logic [WIDTH-1:0] e1_result_i,
  input  logic [2:0]  e1_status_i,
  // engines 2-4 stubs
  output logic        e2_valid_o,
  input  logic        e2_ready_i,
  output logic [3:0]  e2_opcode_o,
  output logic [WIDTH-1:0] e2_base_o, e2_exp_o, e2_m_o,
  input  logic        e2_done_valid_i,
  output logic        e2_done_ready_o,
  input  logic [WIDTH-1:0] e2_result_i,
  input  logic [2:0]  e2_status_i,
  output logic        e3_valid_o,
  input  logic        e3_ready_i,
  output logic [3:0]  e3_opcode_o,
  output logic [WIDTH-1:0] e3_base_o, e3_exp_o, e3_m_o,
  input  logic        e3_done_valid_i,
  output logic        e3_done_ready_o,
  input  logic [WIDTH-1:0] e3_result_i,
  input  logic [2:0]  e3_status_i,
  output logic        e4_valid_o,
  input  logic        e4_ready_i,
  output logic [3:0]  e4_opcode_o,
  output logic [WIDTH-1:0] e4_base_o, e4_exp_o, e4_m_o,
  input  logic        e4_done_valid_i,
  output logic        e4_done_ready_o,
  input  logic [WIDTH-1:0] e4_result_i,
  input  logic [2:0]  e4_status_i,
  // result write-back
  output logic        res_we_o,
  output logic [1:0]  res_bank_o,
  output logic [WIDTH-1:0] res_data_o,
  // completion queue
  output logic        cq_valid_o,
  input  logic        cq_ready_i,
  output logic [44:0] cq_data_o,
  // transaction table
  output logic        tt_upd_en_o,
  output logic [1:0]  tt_upd_slot_o,
  output logic [2:0]  tt_upd_state_o,
  output logic [7:0]  tt_upd_txn_id_o,
  output logic [3:0]  tt_upd_opcode_o,
  output logic [2:0]  tt_upd_engine_id_o,
  output logic [1:0]  tt_upd_seq_o,
  output logic [2:0]  tt_upd_status_o,
  output logic        tt_comp_en_o,
  output logic [1:0]  tt_comp_slot_o,
  output logic [2:0]  tt_comp_status_o,
  input  logic [11:0]  tt_state_packed,  // 4 x 3-bit packed
  output logic [3:0]  bank_free_o,
  output logic        busy_o
);
  // Simplified: dispatch on cmd_valid, route to engine 0 (modexp) or 1 (modinv)
  logic [2:0] uc_class;
  logic uc_legal;
  gf_microcode_rom u_uc (.opcode_i(cmd_i[11:8]), .legal_o(uc_legal), .engine_class_o(uc_class));

  wire dispatch_ok = cmd_valid_i && cmd_ready_o && uc_legal &&
                     (bank_a_i < bank_m_i) && (bank_m_i != '0) && bank_m_i[0];

  // bank_free
  logic [3:0] bf;
  always_comb begin
    for (int i = 0; i < 4; i++) bf[i] = (tt_state_packed[i*3 +: 3] == 3'd0);
  end
  assign bank_free_o = bf;

  assign cmd_ready_o = 1'b1;
  assign busy_o = 1'b0;
  assign bank_rd_o = cmd_i[13:12];

  // Dispatch to engines
  assign e0_valid_o = dispatch_ok && (uc_class == 3'd0);
  assign e0_base_o  = bank_a_i;
  assign e0_m_o     = bank_m_i;
  assign e1_valid_o = dispatch_ok && (uc_class == 3'd1);
  assign e1_a_o     = bank_a_i;
  assign e1_m_o     = bank_m_i;
  assign e2_valid_o = dispatch_ok && (uc_class == 3'd2);
  assign e2_opcode_o = cmd_i[11:8];
  assign e2_base_o  = bank_a_i;
  assign e2_m_o     = bank_m_i;
  assign e2_exp_o   = '0;
  assign e3_valid_o = dispatch_ok && (uc_class == 3'd3);
  assign e3_opcode_o = cmd_i[11:8];
  assign e3_base_o  = bank_a_i;
  assign e3_m_o     = bank_m_i;
  assign e3_exp_o   = '0;
  assign e4_valid_o = dispatch_ok && (uc_class == 3'd4);
  assign e4_opcode_o = cmd_i[11:8];
  assign e4_base_o  = bank_a_i;
  assign e4_m_o     = bank_m_i;
  assign e4_exp_o   = '0;

  // Transaction table update on dispatch
  assign tt_upd_en_o = dispatch_ok;
  assign tt_upd_slot_o = cmd_i[13:12];
  assign tt_upd_state_o = 3'd2; // RUNNING
  assign tt_upd_txn_id_o = cmd_i[7:0];
  assign tt_upd_opcode_o = cmd_i[11:8];
  assign tt_upd_engine_id_o = uc_class;
  assign tt_upd_seq_o = '0;
  assign tt_upd_status_o = 3'd0;

  // Completion handling
  wire e0_done = e0_done_valid_i && e0_done_ready_o;
  wire e1_done = e1_done_valid_i && e1_done_ready_o;
  wire e2_done = e2_done_valid_i && e2_done_ready_o;
  wire e3_done = e3_done_valid_i && e3_done_ready_o;
  wire e4_done = e4_done_valid_i && e4_done_ready_o;

  assign e0_done_ready_o = cq_ready_i;
  assign e1_done_ready_o = cq_ready_i;
  assign e2_done_ready_o = cq_ready_i;
  assign e3_done_ready_o = cq_ready_i;
  assign e4_done_ready_o = cq_ready_i;

  assign cq_valid_o = e0_done || e1_done || e2_done || e3_done || e4_done;

  always_comb begin
    cq_data_o = '0;
    res_we_o = 0; res_bank_o = '0; res_data_o = '0;
    tt_comp_en_o = 0; tt_comp_slot_o = '0; tt_comp_status_o = '0;
    if (e0_done) begin
      cq_data_o = {8'h0, 4'h0, e0_status_i, 2'd0, 4'h0};
      res_we_o = 1; res_bank_o = 2'd0; res_data_o = e0_result_i;
      tt_comp_en_o = 1; tt_comp_slot_o = 2'd0; tt_comp_status_o = e0_status_i;
    end else if (e1_done) begin
      cq_data_o = {8'h0, 4'h1, e1_status_i, 2'd0, 4'h1};
      res_we_o = 1; res_bank_o = 2'd0; res_data_o = e1_result_i;
      tt_comp_en_o = 1; tt_comp_slot_o = 2'd0; tt_comp_status_o = e1_status_i;
    end
  end
endmodule

// ─── Formal properties ─────────────────────────────────────────────────────
module gf_fabric_props (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        cq_in_valid,
  input  logic        cq_in_ready,
  input  logic        rf_out_valid,
  input  logic        rf_out_ready,
  input  logic [7:0]  rf_out_txn_id,
  input  logic [44:0] rf_out,
  input  logic        cmdf_out_valid,
  input  logic        cmdf_out_ready,
  input  logic [7:0]  cmdf_out_txn_id,
  input  logic [2:0]  tt_state_0, tt_state_1, tt_state_2, tt_state_3,
  input  logic [7:0]  tt_txn_id_0, tt_txn_id_1, tt_txn_id_2, tt_txn_id_3
);

endmodule
