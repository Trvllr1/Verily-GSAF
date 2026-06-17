// =============================================================================
// gf_axil_frontend - AXI4-Lite slave: register map, IRQ controller, perf block
// Copyright (c) 2026 Verily. All rights reserved.
//
// Register map (32-bit registers):
//   0x000 CTRL        RW  [0] reserved (soft features)
//   0x004 STATUS      RO  [0] cmd_ready  [1] resp_valid  [4+:NB] bank_free
//   0x008 IRQ_STATUS  W1C [0] completion [1] error
//   0x00C IRQ_ENABLE  RW  [0] completion [1] error
//   0x010 CMD         WO  {bank[13:12], opcode[11:8], txn_id[7:0]} -> command_fifo
//   0x014 RESP        RO  peek: {valid[31], status[14:12], bank[11:10],
//                                opcode[ 9: 8]... see fields below}
//   0x018 RESP_POP    WO  write 1: pop result_fifo, retire txn, WIPE bank
//   0x020 PERF_CYCLES RO  busy cycle count
//   0x024 PERF_TXNS   RO  completed transaction count
//   0x028 PERF_STALLS RO  cycles result_fifo full (host backpressure)
//   0x100 + bank*0x40 + region*0x10 + word*4 : operand windows
//         region 0=A(W) 1=B(W) 2=M(W) 3=RESULT(R)
//         (layout supports WIDTH <= 128; widen stride for larger widths)
//
// Writes to operand windows of a NON-FREE bank are silently dropped
// (transaction isolation: host cannot corrupt in-flight operands).
//
// Host stalls live entirely here; they cannot propagate past result_fifo
// into arithmetic pipelines (spec backpressure firewall).
// =============================================================================
`include "gf_pkg.sv"

module gf_axil_frontend
  import gf_pkg::*;
#(
  parameter int unsigned WIDTH          = gf_pkg::GF_WIDTH_DEFAULT,
  parameter int unsigned EXP_BLIND_BITS = 64,
  // word index sized for the widest region (B, the blinded-exponent region);
  // regmap stride 0x10 supports EXP_W <= 128 (wider widths need v2 regmap)
  localparam int unsigned EXP_W      = WIDTH + EXP_BLIND_BITS,
  localparam int unsigned WORD_IDX_W = $clog2((EXP_W + 31) / 32)
) (
  input  logic                clk_i,
  input  logic                rst_ni,

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

  // command_fifo push side
  output logic        cmd_valid_o,
  input  logic        cmd_ready_i,
  output gf_cmd_t     cmd_o,

  // result_fifo pop side
  input  logic           resp_valid_i,
  output logic           resp_ready_o,
  input  gf_completion_t resp_i,

  // operand bank host ports
  output logic                       hw_we_o,
  output logic [SEQ_W-1:0]           hw_bank_o,
  output logic [1:0]                 hw_region_o,
  output logic [WORD_IDX_W-1:0]      hw_word_o,
  output logic [31:0]                hw_data_o,
  output logic [SEQ_W-1:0]           hr_bank_o,
  output logic [WORD_IDX_W-1:0]      hr_word_o,
  input  logic [31:0]                hr_data_i,

  // retire strobes
  output logic              retire_o,
  output logic [SEQ_W-1:0]  retire_bank_o,

  // status inputs
  input  logic [MAX_TXNS-1:0] bank_free_i,
  input  logic                fabric_busy_i,
  input  logic                result_fifo_full_i
);

  // ---------------------------------------------------------------------------
  // AXI4-Lite write channel (single outstanding)
  // ---------------------------------------------------------------------------
  logic        aw_hs_q, w_hs_q;
  logic [11:0] awaddr_q;
  logic [31:0] wdata_q;

  wire wr_do = aw_hs_q && w_hs_q && !s_axil_bvalid;

  assign s_axil_awready = !aw_hs_q;
  assign s_axil_wready  = !w_hs_q;
  assign s_axil_bresp   = 2'b00;

  // ---------------------------------------------------------------------------
  // AXI4-Lite read channel (single outstanding)
  // ---------------------------------------------------------------------------
  logic        ar_hs_q;
  logic [11:0] araddr_q;

  wire rd_do = ar_hs_q && !s_axil_rvalid;

  assign s_axil_arready = !ar_hs_q;
  assign s_axil_rresp   = 2'b00;

  // ---------------------------------------------------------------------------
  // decode helpers
  // ---------------------------------------------------------------------------
  wire wr_is_bank = awaddr_q[8];                 // 0x100..0x1FF
  wire [SEQ_W-1:0] wr_bank   = awaddr_q[7:6];    // bank*0x40
  wire [1:0]       wr_region = awaddr_q[5:4];    // region*0x10
  wire rd_is_bank = araddr_q[8];
  wire [SEQ_W-1:0] rd_bank   = araddr_q[7:6];
  wire [1:0]       rd_region = araddr_q[5:4];

  // ---------------------------------------------------------------------------
  // registers
  // ---------------------------------------------------------------------------
  logic [1:0]  irq_status_q, irq_enable_q;
  logic [31:0] perf_cycles_q, perf_txns_q, perf_stalls_q;

  assign irq_o = |(irq_status_q & irq_enable_q);

  // command push: held until accepted (cmd_ready_i is STATUS-visible to SW)
  logic    cmd_pend_q;
  gf_cmd_t cmd_q;
  assign cmd_valid_o = cmd_pend_q;
  assign cmd_o       = cmd_q;

  // resp pop / retire
  logic pop_strobe;
  assign resp_ready_o  = pop_strobe;
  assign retire_o      = pop_strobe && resp_valid_i;
  assign retire_bank_o = resp_i.bank;

  // bank write port
  assign hw_we_o     = wr_do && wr_is_bank && (wr_region != 2'd3)
                       && bank_free_i[wr_bank];     // drop writes to busy banks
  assign hw_bank_o   = wr_bank;
  assign hw_region_o = wr_region;
  assign hw_word_o   = awaddr_q[2 +: WORD_IDX_W];
  assign hw_data_o   = wdata_q;

  // bank result read port
  assign hr_bank_o = rd_bank;
  assign hr_word_o = araddr_q[2 +: WORD_IDX_W];

  // ---------------------------------------------------------------------------
  // write side effects
  // ---------------------------------------------------------------------------
  always_comb begin
    pop_strobe = wr_do && !wr_is_bank && (awaddr_q[7:0] == 8'h18) && wdata_q[0];
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      aw_hs_q <= 1'b0; w_hs_q <= 1'b0; ar_hs_q <= 1'b0;
      awaddr_q <= '0; wdata_q <= '0; araddr_q <= '0;
      s_axil_bvalid <= 1'b0;
      s_axil_rvalid <= 1'b0;
      s_axil_rdata  <= '0;
      irq_status_q  <= '0;
      irq_enable_q  <= '0;
      perf_cycles_q <= '0;
      perf_txns_q   <= '0;
      perf_stalls_q <= '0;
      cmd_pend_q    <= 1'b0;
      cmd_q         <= '0;
    end else begin
      // ---- AXI handshakes ----
      if (s_axil_awvalid && s_axil_awready) begin
        aw_hs_q <= 1'b1; awaddr_q <= s_axil_awaddr;
      end
      if (s_axil_wvalid && s_axil_wready) begin
        w_hs_q <= 1'b1; wdata_q <= s_axil_wdata;
      end
      if (wr_do) s_axil_bvalid <= 1'b1;
      if (s_axil_bvalid && s_axil_bready) begin
        s_axil_bvalid <= 1'b0; aw_hs_q <= 1'b0; w_hs_q <= 1'b0;
      end
      if (s_axil_arvalid && s_axil_arready) begin
        ar_hs_q <= 1'b1; araddr_q <= s_axil_araddr;
      end
      if (s_axil_rvalid && s_axil_rready) begin
        s_axil_rvalid <= 1'b0; ar_hs_q <= 1'b0;
      end

      // ---- register writes ----
      if (wr_do && !wr_is_bank) begin
        unique case (awaddr_q[7:0])
          8'h08: irq_status_q <= irq_status_q & ~wdata_q[1:0];   // W1C
          8'h0C: irq_enable_q <= wdata_q[1:0];
          8'h10: if (!cmd_pend_q) begin
            cmd_q      <= '{txn_id: wdata_q[7:0],
                            opcode: gf_opcode_e'(wdata_q[11:8]),
                            bank:   wdata_q[13:12]};
            cmd_pend_q <= 1'b1;
          end
          default: ;
        endcase
      end
      if (cmd_pend_q && cmd_ready_i) cmd_pend_q <= 1'b0;

      // ---- IRQ set events ----
      if (resp_valid_i && resp_ready_o) begin
        irq_status_q[0] <= 1'b1;
        if (resp_i.status != STATUS_OK) irq_status_q[1] <= 1'b1;
      end

      // ---- perf counters ----
      if (fabric_busy_i)      perf_cycles_q <= perf_cycles_q + 1'b1;
      if (retire_o)           perf_txns_q   <= perf_txns_q + 1'b1;
      if (result_fifo_full_i) perf_stalls_q <= perf_stalls_q + 1'b1;

      // ---- register / bank reads ----
      if (rd_do) begin
        s_axil_rvalid <= 1'b1;
        if (rd_is_bank) begin
          s_axil_rdata <= (rd_region == 2'd3) ? hr_data_i : 32'h0;
        end else begin
          unique case (araddr_q[7:0])
            8'h00: s_axil_rdata <= 32'h0;
            8'h04: s_axil_rdata <= {{(28-MAX_TXNS){1'b0}}, bank_free_i,
                                    2'b00, resp_valid_i, !cmd_pend_q};
            8'h08: s_axil_rdata <= {30'h0, irq_status_q};
            8'h0C: s_axil_rdata <= {30'h0, irq_enable_q};
            8'h14: s_axil_rdata <= {resp_valid_i, 14'h0,
                                    resp_i.status, resp_i.bank,
                                    resp_i.opcode, resp_i.txn_id};
            8'h20: s_axil_rdata <= perf_cycles_q;
            8'h24: s_axil_rdata <= perf_txns_q;
            8'h28: s_axil_rdata <= perf_stalls_q;
            default: s_axil_rdata <= 32'hDEAD_BEEF;
          endcase
        end
      end
    end
  end

endmodule
