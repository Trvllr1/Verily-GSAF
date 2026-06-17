// =============================================================================
// tb_gsaf_smoke - Self-checking smoke testbench (AXI4-Lite host model)
// Copyright (c) 2026 Verily. All rights reserved.
//
// Drives the full fabric through the AXI4-Lite frontend using vectors
// generated from the verified Python golden model (model/gen_vectors.py).
//
// Checks:
//   - functional correctness of ModExp / ModInv vs golden model
//   - error-path statuses (invalid modulus, operand >= modulus, reserved op)
//   - simultaneous ModExp + ModInv occupancy (UVM item 5)
//   - in-order retirement when RESPONSE_ORDERING = MODE_IN_ORDER
//   - host backpressure isolation (delayed pops)
//
// Run (any SV-2017 simulator), e.g.:
//   verilator --binary --timing -DGF_ASSERTIONS -Irtl rtl/*.sv tb/tb_gsaf_smoke.sv
//   xrun -sv -define GF_ASSERTIONS rtl/gf_pkg.sv rtl/*.sv tb/tb_gsaf_smoke.sv
// =============================================================================
`timescale 1ns/1ps
`include "gf_pkg.sv"

module tb_gsaf_smoke;
  import gf_pkg::*;

  `include "tb_vectors.svh"

  localparam int unsigned WIDTH  = TB_WIDTH;
  localparam int unsigned EXP_W  = TB_EXP_W;
  localparam int unsigned WORDS  = WIDTH / 32;
  localparam int unsigned EWORDS = EXP_W / 32;

  logic clk = 0;
  logic rst_n = 0;
  always #5 clk = ~clk;

  // AXI4-Lite
  logic        awvalid, awready, wvalid, wready, bvalid, bready;
  logic [11:0] awaddr;
  logic [31:0] wdata;
  logic        arvalid, arready, rvalid, rready;
  logic [11:0] araddr;
  logic [31:0] rdata;
  logic [1:0]  bresp, rresp;
  logic        irq, idle;

  gf_secure_fabric_top #(
    .WIDTH             (WIDTH),
    .RESPONSE_ORDERING (MODE_IN_ORDER),
    .NUM_MULTIPLIERS   (1),
    .EXP_BLIND_BITS    (EXP_W - WIDTH)
  ) dut (
    .clk_i (clk), .rst_ni (rst_n),
    .s_axil_awvalid (awvalid), .s_axil_awready (awready), .s_axil_awaddr (awaddr),
    .s_axil_wvalid  (wvalid),  .s_axil_wready  (wready),  .s_axil_wdata  (wdata),
    .s_axil_wstrb   (4'hF),
    .s_axil_bvalid  (bvalid),  .s_axil_bready  (bready),  .s_axil_bresp  (bresp),
    .s_axil_arvalid (arvalid), .s_axil_arready (arready), .s_axil_araddr (araddr),
    .s_axil_rvalid  (rvalid),  .s_axil_rready  (rready),  .s_axil_rdata  (rdata),
    .s_axil_rresp   (rresp),
    .irq_o (irq), .idle_o (idle)
  );

  int errors = 0;

  // ---------------------------------------------------------------------------
  // AXI4-Lite host tasks
  // ---------------------------------------------------------------------------
  // single-outstanding host: aw/w/ar ready are guaranteed high at issue time
  task automatic axi_write(input logic [11:0] addr, input logic [31:0] data);
    @(posedge clk);
    awvalid <= 1; awaddr <= addr; wvalid <= 1; wdata <= data; bready <= 1;
    @(posedge clk);                  // both handshakes complete here
    awvalid <= 0; wvalid <= 0;
    wait (bvalid);
    @(posedge clk);
    bready <= 0;
  endtask

  task automatic axi_read(input logic [11:0] addr, output logic [31:0] data);
    @(posedge clk);
    arvalid <= 1; araddr <= addr; rready <= 1;
    @(posedge clk);
    arvalid <= 0;
    wait (rvalid);
    data = rdata;
    @(posedge clk);
    rready <= 0;
  endtask

  // ---------------------------------------------------------------------------
  // fabric driver helpers
  // ---------------------------------------------------------------------------
  // region B (exponent) is EXP_W bits wide to carry blinded exponents;
  // A and M are WIDTH bits
  task automatic load_operand(input logic [1:0] bank, input logic [1:0] region,
                              input logic [EXP_W-1:0] value, input int nwords);
    for (int w = 0; w < nwords; w++)
      axi_write(12'h100 + bank*12'h40 + region*12'h10 + 12'(w*4),
                value[w*32 +: 32]);
  endtask

  task automatic submit(input logic [1:0] bank, input logic [3:0] opcode,
                        input logic [7:0] txn_id);
    axi_write(12'h010, {18'h0, bank, opcode, txn_id});
  endtask

  // wait for a response, check it, read result, pop/retire
  task automatic collect(input logic [7:0] exp_txn,
                         input logic [2:0] exp_status,
                         input logic [WIDTH-1:0] exp_result,
                         input int backpressure_cycles = 0);
    logic [31:0] resp, word;
    logic [WIDTH-1:0] res;
    logic [1:0] bank;
    int guard = 0;
    forever begin
      axi_read(12'h014, resp);
      if (resp[31]) break;
      guard++;
      if (guard > 200_000) begin
        $display("[FAIL] timeout waiting for response txn=%0h", exp_txn);
        errors++; return;
      end
    end
    // deliberate host stall: must not affect anything
    repeat (backpressure_cycles) @(posedge clk);

    if (resp[7:0] !== exp_txn) begin
      $display("[FAIL] txn order: got %02h want %02h", resp[7:0], exp_txn);
      errors++;
    end
    if (resp[16:14] !== exp_status) begin
      $display("[FAIL] txn %02h status: got %0d want %0d",
               exp_txn, resp[16:14], exp_status);
      errors++;
    end
    bank = resp[13:12];
    if (exp_status == 3'd0) begin
      for (int w = 0; w < WORDS; w++) begin
        axi_read(12'h100 + bank*12'h40 + 12'h30 + 12'(w*4), word);
        res[w*32 +: 32] = word;
      end
      if (res !== exp_result) begin
        $display("[FAIL] txn %02h result: got %h want %h", exp_txn, res, exp_result);
        errors++;
      end
    end
    axi_write(12'h018, 32'h1);   // pop + retire + wipe
  endtask

  // ---------------------------------------------------------------------------
  // test sequence
  // ---------------------------------------------------------------------------
  initial begin
    logic [31:0] st;

    awvalid = 0; wvalid = 0; bready = 0; arvalid = 0; rready = 0;
    repeat (5) @(posedge clk);
    rst_n = 1;
    repeat (2) @(posedge clk);

    // ---- phase 1: serial vectors, each checked against the golden model ----
    load_vectors();
    for (int i = 0; i < N_VECTORS; i++) begin
      load_operand(2'd0, 2'd0, {{(EXP_W-WIDTH){1'b0}}, vectors[i].a}, WORDS);
      load_operand(2'd0, 2'd1, vectors[i].b, EWORDS);
      load_operand(2'd0, 2'd2, {{(EXP_W-WIDTH){1'b0}}, vectors[i].m}, WORDS);
      submit(2'd0, vectors[i].opcode, 8'(i));
      collect(8'(i), vectors[i].exp_status, vectors[i].exp_result,
              (i % 7 == 0) ? 50 : 0);     // periodic host backpressure
      if (i % 8 == 0) $display("[info] vector %0d/%0d done", i, N_VECTORS);
    end

    // ---- phase 2: simultaneous ModExp + ModInv, in-order retirement ----
    begin
      logic [WIDTH-1:0] m1, a1, e1, m2, a2, r_exp, r_inv;
      m1 = 64'hFFFF_FFFF_FFFF_FFC5; a1 = 64'h1234_5678_9ABC_DEF1;
      e1 = 64'h0FED_CBA9_8765_4321;
      m2 = 64'hFFFF_FFFF_FFFF_FF61; a2 = 64'h0BAD_C0DE_0000_0007;
      // golden expectations injected by gen_vectors? compute here via DPI-free
      // route: use vectors regenerated offline. For smoke, reuse python-known:
      r_exp = pexp(a1, e1, m1);
      r_inv = pinv(a2, m2);
      load_operand(2'd1, 2'd0, {{(EXP_W-WIDTH){1'b0}}, a1}, WORDS);
      load_operand(2'd1, 2'd1, {{(EXP_W-WIDTH){1'b0}}, e1}, EWORDS);
      load_operand(2'd1, 2'd2, {{(EXP_W-WIDTH){1'b0}}, m1}, WORDS);
      load_operand(2'd2, 2'd0, {{(EXP_W-WIDTH){1'b0}}, a2}, WORDS);
      load_operand(2'd2, 2'd1, '0, EWORDS);
      load_operand(2'd2, 2'd2, {{(EXP_W-WIDTH){1'b0}}, m2}, WORDS);
      submit(2'd1, 4'h0, 8'hE0);    // modexp first (slower)
      submit(2'd2, 4'h1, 8'hE1);    // modinv concurrently (finishes first)
      // MODE_IN_ORDER: E0 must retire before E1 despite E1 completing first
      collect(8'hE0, 3'd0, r_exp);
      collect(8'hE1, 3'd0, r_inv);
    end

    // ---- done ----
    axi_read(12'h024, st);
    $display("[info] PERF_TXNS = %0d", st);
    if (errors == 0) $display("\nTB PASS: all %0d vectors + concurrency test", N_VECTORS);
    else             $display("\nTB FAIL: %0d errors", errors);
    $finish;
  end

  // reference functions for phase 2 (mirror golden model, simulation-only;
  // '**'/'%' permitted in TB code, never in RTL datapaths)
  function automatic logic [WIDTH-1:0] pexp(input logic [WIDTH-1:0] a, e, m);
    logic [2*WIDTH-1:0] acc, b;
    acc = 1; b = a;
    for (int i = 0; i < WIDTH; i++) begin
      if (e[i]) acc = (acc * b) % m;
      b = (b * b) % m;
    end
    return acc[WIDTH-1:0];
  endfunction

  function automatic logic [WIDTH-1:0] pinv(input logic [WIDTH-1:0] a, m);
    // extended Euclid (TB-only)
    longint unsigned r0, r1, t;
    logic signed [2*WIDTH:0] s0, s1, q, tmp;
    r0 = m; r1 = a; s0 = 0; s1 = 1;
    while (r1 != 0) begin
      q  = r0 / r1;
      t  = r0 - q*r1; r0 = r1; r1 = t;
      tmp = s0 - q*s1; s0 = s1; s1 = tmp;
    end
    if (s0 < 0) s0 += m;
    return s0[WIDTH-1:0];
  endfunction

  initial begin
    #200ms;
    $display("TB FAIL: global timeout");
    $finish;
  end

endmodule
