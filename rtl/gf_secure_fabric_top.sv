// =============================================================================
// gf_secure_fabric_top - GreenField Secure Arithmetic Fabric, top level
// Copyright (c) 2026 Verily. All rights reserved.
//
//   axi_frontend -> command_fifo -> scheduler -> { modexp, modinv, PQC,
//   RSA-CRT, ECC } -> completion_queue -> reorder_buffer -> result_fifo ->
//   axi_frontend
//
// Backpressure firewall: engines never touch result_fifo; host stalls are
// absorbed in result_fifo/ROB and can never reach arithmetic pipelines.
// Clock gating: no manual gates anywhere; idle_o exported for tool ICG.
// =============================================================================
`include "gf_pkg.sv"

module gf_secure_fabric_top
  import gf_pkg::*;
#(
  parameter int unsigned    WIDTH             = gf_pkg::GF_WIDTH_DEFAULT,
  parameter gf_order_mode_e RESPONSE_ORDERING = MODE_OOO,
  parameter int unsigned    NUM_MULTIPLIERS   = 3,
  // DPA countermeasure: exponent datapath is WIDTH + EXP_BLIND_BITS wide so
  // hosts can submit blinded exponents d' = d + k*lambda(m)
  parameter int unsigned    EXP_BLIND_BITS    = 64,
  localparam int unsigned   EXP_W             = WIDTH + EXP_BLIND_BITS
) (
  input  logic        clk_i,
  input  logic        rst_ni,

  // AXI4-Lite slave
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
  output logic        idle_o      // for tool-inserted clock gating
);

  // ---------------------------------------------------------------------------
  // frontend <-> fabric wiring
  // ---------------------------------------------------------------------------
  logic           cmdf_in_valid, cmdf_in_ready;
  gf_cmd_t        cmdf_in;
  logic           cmdf_out_valid, cmdf_out_ready;
  gf_cmd_t        cmdf_out;

  logic           cq_in_valid, cq_in_ready;
  gf_completion_t cq_in;
  logic           cq_out_valid, cq_out_ready;
  gf_completion_t cq_out;

  logic           rob_out_valid, rob_out_ready;
  gf_completion_t rob_out;

  logic           rf_out_valid, rf_out_ready;
  gf_completion_t rf_out;
  logic           rf_in_ready;
  logic [$clog2(MAX_TXNS+1)-1:0] rf_count;

  // operand bank ports
  logic                       hw_we;
  logic [SEQ_W-1:0]           hw_bank;
  logic [1:0]                 hw_region;
  logic [$clog2((EXP_W+31)/32)-1:0] hw_word, hr_word;
  logic [31:0]                hw_data, hr_data;
  logic [SEQ_W-1:0]           hr_bank;
  logic [SEQ_W-1:0]           bank_rd;
  logic [WIDTH-1:0]           bank_a, bank_m;
  logic [EXP_W-1:0]           bank_b;
  logic                       res_we;
  logic [SEQ_W-1:0]           res_bank;
  logic [WIDTH-1:0]           res_data;
  logic                       retire;
  logic [SEQ_W-1:0]           retire_bank;

  // ---------------------------------------------------------------------------
  // engine 0: modexp
  // ---------------------------------------------------------------------------
  logic             e0_cmd_valid, e0_cmd_ready;
  logic [WIDTH-1:0] e0_base, e0_m;
  logic [EXP_W-1:0] e0_exp;
  logic             e0_done_valid, e0_done_ready;
  logic [WIDTH-1:0] e0_result;
  gf_status_e       e0_status;
  logic             e0_idle;

  // ---------------------------------------------------------------------------
  // engine 1: modinv
  // ---------------------------------------------------------------------------
  logic             e1_cmd_valid, e1_cmd_ready;
  logic [WIDTH-1:0] e1_a, e1_m;
  logic             e1_done_valid, e1_done_ready;
  logic [WIDTH-1:0] e1_result;
  gf_status_e       e1_status;
  logic             e1_idle;

  // ---------------------------------------------------------------------------
  // engine 2: PQC
  // ---------------------------------------------------------------------------
  logic             e2_cmd_valid, e2_cmd_ready;
  logic [3:0]       e2_opcode;
  logic [WIDTH-1:0] e2_base, e2_exp, e2_m;
  logic             e2_done_valid, e2_done_ready;
  logic [WIDTH-1:0] e2_result;
  gf_status_e       e2_status;
  logic             e2_idle;

  // ---------------------------------------------------------------------------
  // engine 3: RSA-CRT
  // ---------------------------------------------------------------------------
  logic             e3_cmd_valid, e3_cmd_ready;
  logic [3:0]       e3_opcode;
  logic [WIDTH-1:0] e3_base, e3_exp, e3_m;
  logic             e3_done_valid, e3_done_ready;
  logic [WIDTH-1:0] e3_result;
  gf_status_e       e3_status;
  logic             e3_idle;

  // ---------------------------------------------------------------------------
  // engine 4: ECC
  // ---------------------------------------------------------------------------
  logic             e4_cmd_valid, e4_cmd_ready;
  logic [3:0]       e4_opcode;
  logic [WIDTH-1:0] e4_base, e4_exp, e4_m;
  logic             e4_done_valid, e4_done_ready;
  logic [WIDTH-1:0] e4_result;
  gf_status_e       e4_status;
  logic             e4_idle;

  // montgomery cluster lanes (statically reserved: lane 0 = modexp, lane 1 = RSA-CRT, lane 2 = ECC)
  logic             mc_req_valid [NUM_MULTIPLIERS];
  logic             mc_req_ready [NUM_MULTIPLIERS];
  logic [WIDTH-1:0] mc_a [NUM_MULTIPLIERS];
  logic [WIDTH-1:0] mc_b [NUM_MULTIPLIERS];
  logic [WIDTH-1:0] mc_m [NUM_MULTIPLIERS];
  logic             mc_rsp_valid [NUM_MULTIPLIERS];
  logic             mc_rsp_ready [NUM_MULTIPLIERS];
  logic [WIDTH-1:0] mc_p [NUM_MULTIPLIERS];
  logic             mc_idle;

  // PQC multiplier lane (dedicated, separate from Montgomery cluster)
  logic             pqc_mul_req_valid, pqc_mul_req_ready;
  logic [WIDTH-1:0] pqc_mul_a, pqc_mul_b, pqc_mul_m;
  logic             pqc_mul_rsp_valid, pqc_mul_rsp_ready;
  logic [WIDTH-1:0] pqc_mul_p;

  // transaction table
  logic                tt_upd_en;
  logic [SEQ_W-1:0]    tt_upd_slot;
  gf_txn_state_e       tt_upd_state;
  logic [TXN_ID_W-1:0] tt_upd_txn_id;
  gf_opcode_e          tt_upd_opcode;
  logic [2:0]          tt_upd_engine_id;
  logic [SEQ_W-1:0]    tt_upd_seq;
  gf_status_e          tt_upd_status;
  logic                tt_comp_en;
  logic [SEQ_W-1:0]    tt_comp_slot;
  gf_status_e          tt_comp_status;
  gf_txn_state_e       tt_state   [MAX_TXNS];
  logic [TXN_ID_W-1:0] tt_txn_id  [MAX_TXNS];
  gf_opcode_e          tt_opcode  [MAX_TXNS];
  logic [SEQ_W-1:0]    tt_seq     [MAX_TXNS];
  gf_status_e          tt_status  [MAX_TXNS];

  logic [MAX_TXNS-1:0] bank_free;
  logic                sched_busy;

  // ---------------------------------------------------------------------------
  // axi_frontend (includes irq_controller + performance_counter_block)
  // ---------------------------------------------------------------------------
  gf_axil_frontend #(
    .WIDTH          (WIDTH),
    .EXP_BLIND_BITS (EXP_BLIND_BITS)
  ) u_frontend (
    .clk_i, .rst_ni,
    .s_axil_awvalid, .s_axil_awready, .s_axil_awaddr,
    .s_axil_wvalid,  .s_axil_wready,  .s_axil_wdata, .s_axil_wstrb,
    .s_axil_bvalid,  .s_axil_bready,  .s_axil_bresp,
    .s_axil_arvalid, .s_axil_arready, .s_axil_araddr,
    .s_axil_rvalid,  .s_axil_rready,  .s_axil_rdata, .s_axil_rresp,
    .irq_o,
    .cmd_valid_o   (cmdf_in_valid),
    .cmd_ready_i   (cmdf_in_ready),
    .cmd_o         (cmdf_in),
    .resp_valid_i  (rf_out_valid),
    .resp_ready_o  (rf_out_ready),
    .resp_i        (rf_out),
    .hw_we_o       (hw_we),
    .hw_bank_o     (hw_bank),
    .hw_region_o   (hw_region),
    .hw_word_o     (hw_word),
    .hw_data_o     (hw_data),
    .hr_bank_o     (hr_bank),
    .hr_word_o     (hr_word),
    .hr_data_i     (hr_data),
    .retire_o      (retire),
    .retire_bank_o (retire_bank),
    .bank_free_i   (bank_free),
    .fabric_busy_i (sched_busy),
    .result_fifo_full_i (!rf_in_ready)
  );

  // ---------------------------------------------------------------------------
  // command_fifo
  // ---------------------------------------------------------------------------
  gf_fifo #(.DATA_W($bits(gf_cmd_t)), .DEPTH(MAX_TXNS)) u_command_fifo (
    .clk_i, .rst_ni,
    .valid_i (cmdf_in_valid),
    .ready_o (cmdf_in_ready),
    .data_i  (cmdf_in),
    .valid_o (cmdf_out_valid),
    .ready_i (cmdf_out_ready),
    .data_o  (cmdf_out),
    .count_o ()
  );

  // ---------------------------------------------------------------------------
  // operand banks (bank0..bank3)
  // ---------------------------------------------------------------------------
  gf_operand_banks #(
    .WIDTH          (WIDTH),
    .EXP_BLIND_BITS (EXP_BLIND_BITS)
  ) u_operand_banks (
    .clk_i, .rst_ni,
    .hw_we_i     (hw_we),
    .hw_bank_i   (hw_bank),
    .hw_region_i (hw_region),
    .hw_word_i   (hw_word),
    .hw_data_i   (hw_data),
    .hr_bank_i   (hr_bank),
    .hr_word_i   (hr_word),
    .hr_data_o   (hr_data),
    .rd_bank_i   (bank_rd),
    .rd_a_o      (bank_a),
    .rd_b_o      (bank_b),
    .rd_m_o      (bank_m),
    .res_we_i    (res_we),
    .res_bank_i  (res_bank),
    .res_data_i  (res_data),
    .wipe_i      (retire),
    .wipe_bank_i (retire_bank)
  );

  // ---------------------------------------------------------------------------
  // transaction_table
  // ---------------------------------------------------------------------------
  gf_transaction_table u_transaction_table (
    .clk_i, .rst_ni,
    .upd_en_i        (tt_upd_en),
    .upd_slot_i      (tt_upd_slot),
    .upd_state_i     (tt_upd_state),
    .upd_txn_id_i    (tt_upd_txn_id),
    .upd_opcode_i    (tt_upd_opcode),
    .upd_engine_id_i (tt_upd_engine_id),
    .upd_seq_i       (tt_upd_seq),
    .upd_status_i    (tt_upd_status),
    .ret_en_i        (retire),
    .ret_slot_i      (retire_bank),
    .comp_en_i       (tt_comp_en),
    .comp_slot_i     (tt_comp_slot),
    .comp_status_i   (tt_comp_status),
    .state_o         (tt_state),
    .txn_id_o        (tt_txn_id),
    .opcode_o        (tt_opcode),
    .seq_o           (tt_seq),
    .status_o        (tt_status)
  );

  // ---------------------------------------------------------------------------
  // scheduler
  // ---------------------------------------------------------------------------
  gf_scheduler #(
    .WIDTH          (WIDTH),
    .EXP_BLIND_BITS (EXP_BLIND_BITS)
  ) u_scheduler (
    .clk_i, .rst_ni,
    .cmd_valid_i (cmdf_out_valid),
    .cmd_ready_o (cmdf_out_ready),
    .cmd_i       (cmdf_out),
    .bank_rd_o   (bank_rd),
    .bank_a_i    (bank_a),
    .bank_b_i    (bank_b),
    .bank_m_i    (bank_m),
    // engine 0: modexp
    .e0_valid_o  (e0_cmd_valid),
    .e0_ready_i  (e0_cmd_ready),
    .e0_base_o   (e0_base),
    .e0_exp_o    (e0_exp),
    .e0_m_o      (e0_m),
    .e0_done_valid_i (e0_done_valid),
    .e0_done_ready_o (e0_done_ready),
    .e0_result_i (e0_result),
    .e0_status_i (e0_status),
    // engine 1: modinv
    .e1_valid_o  (e1_cmd_valid),
    .e1_ready_i  (e1_cmd_ready),
    .e1_a_o      (e1_a),
    .e1_m_o      (e1_m),
    .e1_done_valid_i (e1_done_valid),
    .e1_done_ready_o (e1_done_ready),
    .e1_result_i (e1_result),
    .e1_status_i (e1_status),
    // engine 2: PQC
    .e2_valid_o  (e2_cmd_valid),
    .e2_ready_i  (e2_cmd_ready),
    .e2_opcode_o (e2_opcode),
    .e2_base_o   (e2_base),
    .e2_exp_o    (e2_exp),
    .e2_m_o      (e2_m),
    .e2_done_valid_i (e2_done_valid),
    .e2_done_ready_o (e2_done_ready),
    .e2_result_i (e2_result),
    .e2_status_i (e2_status),
    // engine 3: RSA-CRT
    .e3_valid_o  (e3_cmd_valid),
    .e3_ready_i  (e3_cmd_ready),
    .e3_opcode_o (e3_opcode),
    .e3_base_o   (e3_base),
    .e3_exp_o    (e3_exp),
    .e3_m_o      (e3_m),
    .e3_done_valid_i (e3_done_valid),
    .e3_done_ready_o (e3_done_ready),
    .e3_result_i (e3_result),
    .e3_status_i (e3_status),
    // engine 4: ECC
    .e4_valid_o  (e4_cmd_valid),
    .e4_ready_i  (e4_cmd_ready),
    .e4_opcode_o (e4_opcode),
    .e4_base_o   (e4_base),
    .e4_exp_o    (e4_exp),
    .e4_m_o      (e4_m),
    .e4_done_valid_i (e4_done_valid),
    .e4_done_ready_o (e4_done_ready),
    .e4_result_i (e4_result),
    .e4_status_i (e4_status),
    // result write-back
    .res_we_o    (res_we),
    .res_bank_o  (res_bank),
    .res_data_o  (res_data),
    // completion queue
    .cq_valid_o  (cq_in_valid),
    .cq_ready_i  (cq_in_ready),
    .cq_data_o   (cq_in),
    // transaction table
    .tt_upd_en_o        (tt_upd_en),
    .tt_upd_slot_o      (tt_upd_slot),
    .tt_upd_state_o     (tt_upd_state),
    .tt_upd_txn_id_o    (tt_upd_txn_id),
    .tt_upd_opcode_o    (tt_upd_opcode),
    .tt_upd_engine_id_o (tt_upd_engine_id),
    .tt_upd_seq_o       (tt_upd_seq),
    .tt_upd_status_o    (tt_upd_status),
    .tt_comp_en_o       (tt_comp_en),
    .tt_comp_slot_o     (tt_comp_slot),
    .tt_comp_status_o   (tt_comp_status),
    .tt_state_i         (tt_state),
    .bank_free_o (bank_free),
    .busy_o      (sched_busy)
  );

  // ---------------------------------------------------------------------------
  // engine 0: modexp (uses Montgomery cluster lane 0)
  // ---------------------------------------------------------------------------
  gf_modexp_engine #(
    .WIDTH          (WIDTH),
    .EXP_BLIND_BITS (EXP_BLIND_BITS)
  ) u_modexp_engine (
    .clk_i, .rst_ni,
    .valid_i  (e0_cmd_valid),
    .ready_o  (e0_cmd_ready),
    .base_i   (e0_base),
    .exp_i    (e0_exp),
    .m_i      (e0_m),
    .valid_o  (e0_done_valid),
    .ready_i  (e0_done_ready),
    .result_o (e0_result),
    .status_o (e0_status),
    .mul_req_valid_o (mc_req_valid[0]),
    .mul_req_ready_i (mc_req_ready[0]),
    .mul_a_o         (mc_a[0]),
    .mul_b_o         (mc_b[0]),
    .mul_m_o         (mc_m[0]),
    .mul_rsp_valid_i (mc_rsp_valid[0]),
    .mul_rsp_ready_o (mc_rsp_ready[0]),
    .mul_p_i         (mc_p[0]),
    .idle_o   (e0_idle)
  );

  // ---------------------------------------------------------------------------
  // engine 1: modinv
  // ---------------------------------------------------------------------------
  gf_modinv_engine #(.WIDTH(WIDTH)) u_modinv_engine (
    .clk_i, .rst_ni,
    .valid_i  (e1_cmd_valid),
    .ready_o  (e1_cmd_ready),
    .a_i      (e1_a),
    .m_i      (e1_m),
    .valid_o  (e1_done_valid),
    .ready_i  (e1_done_ready),
    .result_o (e1_result),
    .status_o (e1_status),
    .idle_o   (e1_idle)
  );

  // ---------------------------------------------------------------------------
  // engine 2: PQC (dedicated multiplier via gf_engine_if)
  // ---------------------------------------------------------------------------
  gf_engine_if #(.WIDTH(WIDTH), .EXP_W(WIDTH)) pqc_engine_if (
    .clk_i  (clk_i),
    .rst_ni (rst_ni)
  );

  gf_pqc_engine_wrapper #(
    .WIDTH (WIDTH),
    .N     (256),
    .Q     (8380417)
  ) u_pqc_wrapper (
    .clk_i          (clk_i),
    .rst_ni         (rst_ni),
    .engine_if      (pqc_engine_if),
    .mul_req_valid_o(pqc_mul_req_valid),
    .mul_req_ready_i(pqc_mul_req_ready),
    .mul_a_o        (pqc_mul_a),
    .mul_b_o        (pqc_mul_b),
    .mul_m_o        (pqc_mul_m),
    .mul_rsp_valid_i(pqc_mul_rsp_valid),
    .mul_rsp_ready_o(pqc_mul_rsp_ready),
    .mul_p_i        (pqc_mul_p),
    .coeff_wr_en    (),
    .coeff_wr_addr  (),
    .coeff_wr_data  (),
    .coeff_rd_en    (),
    .coeff_rd_addr  (),
    .coeff_rd_data  ('0)
  );

  // PQC engine <-> scheduler wiring
  assign e2_cmd_ready   = pqc_engine_if.cmd_ready;
  assign pqc_engine_if.cmd_valid  = e2_cmd_valid;
  assign pqc_engine_if.cmd_opcode = e2_opcode;
  assign pqc_engine_if.cmd_txn_id = '0;
  assign pqc_engine_if.cmd_base   = e2_base;
  assign pqc_engine_if.cmd_exp    = e2_exp;
  assign pqc_engine_if.cmd_m      = e2_m;
  assign e2_done_valid  = pqc_engine_if.rsp_valid;
  assign pqc_engine_if.rsp_ready  = e2_done_ready;
  assign e2_result      = pqc_engine_if.rsp_result;
  assign e2_status      = pqc_engine_if.rsp_status;
  assign e2_idle        = pqc_engine_if.engine_idle;

  // PQC multiplier lane (dedicated, not from Montgomery cluster)
  gf_mont_mult #(.WIDTH(WIDTH)) u_pqc_mult (
    .clk_i, .rst_ni,
    .req_valid_i(pqc_mul_req_valid),
    .req_ready_o(pqc_mul_req_ready),
    .req_a_i    (pqc_mul_a),
    .req_b_i    (pqc_mul_b),
    .req_m_i    (pqc_mul_m),
    .rsp_valid_o(pqc_mul_rsp_valid),
    .rsp_ready_i(pqc_mul_rsp_ready),
    .rsp_p_o    (pqc_mul_p)
  );

  // ---------------------------------------------------------------------------
  // engine 3: RSA-CRT (uses Montgomery cluster lane 1)
  // ---------------------------------------------------------------------------
  gf_engine_if #(.WIDTH(WIDTH), .EXP_W(WIDTH)) rsa_crt_engine_if (
    .clk_i  (clk_i),
    .rst_ni (rst_ni)
  );

  gf_rsa_crt_engine_wrapper #(
    .WIDTH (WIDTH),
    .EXP_W (WIDTH)
  ) u_rsa_crt_wrapper (
    .clk_i          (clk_i),
    .rst_ni         (rst_ni),
    .engine_if      (rsa_crt_engine_if),
    .rsa_p_i        ('0),  // TODO: connect to operand bank for RSA-CRT-specific inputs
    .rsa_q_i        ('0),
    .rsa_dp_i       ('0),
    .rsa_dq_i       ('0),
    .rsa_qinv_i     ('0),
    .mul_req_valid_o(mc_req_valid[1]),
    .mul_req_ready_i(mc_req_ready[1]),
    .mul_a_o        (mc_a[1]),
    .mul_b_o        (mc_b[1]),
    .mul_m_o        (mc_m[1]),
    .mul_rsp_valid_i(mc_rsp_valid[1]),
    .mul_rsp_ready_o(mc_rsp_ready[1]),
    .mul_p_i        (mc_p[1])
  );

  // RSA-CRT engine <-> scheduler wiring
  assign e3_cmd_ready   = rsa_crt_engine_if.cmd_ready;
  assign rsa_crt_engine_if.cmd_valid  = e3_cmd_valid;
  assign rsa_crt_engine_if.cmd_opcode = e3_opcode;
  assign rsa_crt_engine_if.cmd_txn_id = '0;
  assign rsa_crt_engine_if.cmd_base   = e3_base;
  assign rsa_crt_engine_if.cmd_exp    = e3_exp;
  assign rsa_crt_engine_if.cmd_m      = e3_m;
  assign e3_done_valid  = rsa_crt_engine_if.rsp_valid;
  assign rsa_crt_engine_if.rsp_ready  = e3_done_ready;
  assign e3_result      = rsa_crt_engine_if.rsp_result;
  assign e3_status      = rsa_crt_engine_if.rsp_status;
  assign e3_idle        = rsa_crt_engine_if.engine_idle;

  // ---------------------------------------------------------------------------
  // engine 4: ECC (uses Montgomery cluster lane 2)
  // ---------------------------------------------------------------------------
  gf_engine_if #(.WIDTH(WIDTH), .EXP_W(WIDTH)) ecc_engine_if (
    .clk_i  (clk_i),
    .rst_ni (rst_ni)
  );

  gf_ecc_engine_wrapper #(
    .WIDTH      (WIDTH),
    .CURVE_TYPE (0)  // X25519
  ) u_ecc_wrapper (
    .clk_i          (clk_i),
    .rst_ni         (rst_ni),
    .engine_if      (ecc_engine_if),
    .mul_req_valid_o(mc_req_valid[2]),
    .mul_req_ready_i(mc_req_ready[2]),
    .mul_a_o        (mc_a[2]),
    .mul_b_o        (mc_b[2]),
    .mul_m_o        (mc_m[2]),
    .mul_rsp_valid_i(mc_rsp_valid[2]),
    .mul_rsp_ready_o(mc_rsp_ready[2]),
    .mul_p_i        (mc_p[2])
  );

  // ECC engine <-> scheduler wiring
  assign e4_cmd_ready   = ecc_engine_if.cmd_ready;
  assign ecc_engine_if.cmd_valid  = e4_cmd_valid;
  assign ecc_engine_if.cmd_opcode = e4_opcode;
  assign ecc_engine_if.cmd_txn_id = '0;
  assign ecc_engine_if.cmd_base   = e4_base;
  assign ecc_engine_if.cmd_exp    = e4_exp;
  assign ecc_engine_if.cmd_m      = e4_m;
  assign e4_done_valid  = ecc_engine_if.rsp_valid;
  assign ecc_engine_if.rsp_ready  = e4_done_ready;
  assign e4_result      = ecc_engine_if.rsp_result;
  assign e4_status      = ecc_engine_if.rsp_status;
  assign e4_idle        = ecc_engine_if.engine_idle;

  // ---------------------------------------------------------------------------
  // montgomery_cluster (3 multiplier lanes: modexp, RSA-CRT, ECC)
  // ---------------------------------------------------------------------------
  gf_montgomery_cluster #(
    .WIDTH           (WIDTH),
    .NUM_MULTIPLIERS (NUM_MULTIPLIERS)
  ) u_montgomery_cluster (
    .clk_i, .rst_ni,
    .req_valid_i (mc_req_valid),
    .req_ready_o (mc_req_ready),
    .req_a_i     (mc_a),
    .req_b_i     (mc_b),
    .req_m_i     (mc_m),
    .rsp_valid_o (mc_rsp_valid),
    .rsp_ready_i (mc_rsp_ready),
    .rsp_p_o     (mc_p),
    .idle_o      (mc_idle)
  );

  // ---------------------------------------------------------------------------
  // completion_queue -> reorder_buffer -> result_fifo
  // ---------------------------------------------------------------------------
  gf_completion_queue u_completion_queue (
    .clk_i, .rst_ni,
    .valid_i (cq_in_valid),
    .ready_o (cq_in_ready),
    .data_i  (cq_in),
    .valid_o (cq_out_valid),
    .ready_i (cq_out_ready),
    .data_o  (cq_out),
    .count_o ()
  );

  gf_reorder_buffer #(.RESPONSE_ORDERING(RESPONSE_ORDERING)) u_reorder_buffer (
    .clk_i, .rst_ni,
    .valid_i (cq_out_valid),
    .ready_o (cq_out_ready),
    .data_i  (cq_out),
    .valid_o (rob_out_valid),
    .ready_i (rob_out_ready),
    .data_o  (rob_out)
  );

  gf_fifo #(.DATA_W($bits(gf_completion_t)), .DEPTH(MAX_TXNS)) u_result_fifo (
    .clk_i, .rst_ni,
    .valid_i (rob_out_valid),
    .ready_o (rob_out_ready),
    .data_i  (rob_out),
    .valid_o (rf_out_valid),
    .ready_i (rf_out_ready),
    .data_o  (rf_out),
    .count_o (rf_count)
  );
  assign rf_in_ready = rob_out_ready;

  // ---------------------------------------------------------------------------
  // idle for tool-inserted clock gating
  // ---------------------------------------------------------------------------
  assign idle_o = e0_idle && e1_idle && e2_idle && e3_idle && e4_idle &&
                  mc_idle && !sched_busy && !cq_out_valid && !rf_out_valid;

endmodule
