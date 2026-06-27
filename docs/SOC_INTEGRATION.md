# GSAF SoC Integration Guide

## Overview

This guide explains how to integrate the GSAF cryptographic fabric into a System-on-Chip (SoC) design. GSAF exposes an AXI4-Lite slave interface, making it straightforward to connect to any standard bus fabric.

## Integration Architecture

```
                    ┌─────────────────────────────┐
                    │         SoC Bus Fabric        │
                    │    (AXI Interconnect/NoC)     │
                    └──────────┬──────────────────┘
                               │ AXI4-Lite
                    ┌──────────▼──────────────────┐
                    │     gf_secure_fabric_top      │
                    │  ┌────────────────────────┐  │
                    │  │  gf_axil_frontend       │  │  Register map
                    │  │  (regmap + IRQ + perf)  │  │  + interrupt
                    │  └──────────┬─────────────┘  │
                    │             │                  │
                    │  ┌──────────▼─────────────┐  │
                    │  │  gf_scheduler           │  │  Command dispatch
                    │  │  (microcode + screening)│  │  + input validation
                    │  └──────────┬─────────────┘  │
                    │             │                  │
                    │  ┌──────────▼─────────────┐  │
                    │  │  Engine Slot 0: ModExp  │  │
                    │  │  Engine Slot 1: ModInv  │  │  Pluggable engines
                    │  │  Engine Slot 2: PQC     │  │  via gf_engine_if
                    │  │  Engine Slot 3: RSA-CRT │  │
                    │  │  Engine Slot 4: ECC     │  │
                    │  └──────────┬─────────────┘  │
                    │             │                  │
                    │  ┌──────────▼─────────────┐  │
                    │  │  gf_montgomery_cluster  │  │  Static lane reservation
                    │  │  (1-8 multiplier lanes) │  │  No arbitration
                    │  └────────────────────────┘  │
                    └─────────────────────────────┘
```

## Step 1: Connect to AXI4-Lite Bus

GSAF exposes a standard AXI4-Lite slave interface. Connect it to your bus interconnect:

```systemverilog
gf_secure_fabric_top #(
    .WIDTH          (64),        // Data path width (64-bit default)
    .NUM_MULTIPLIERS(1),         // 1-8 multiplier lanes
    .MAX_TXNS       (4),         // In-flight transaction depth
    .EXP_BLIND_BITS (64)         // DPA exponent blinding width
) u_gsaf (
    .clk_i          (sys_clk),
    .rst_ni         (sys_rst_n),
    // AXI4-Lite slave
    .s_axil_awvalid (bus_awvalid),
    .s_axil_awready (bus_awready),
    .s_axil_awaddr  (bus_awaddr[11:0]),
    .s_axil_wvalid  (bus_wvalid),
    .s_axil_wready  (bus_wready),
    .s_axil_wdata   (bus_wdata[31:0]),
    .s_axil_wstrb   (bus_wstrb[3:0]),
    .s_axil_bvalid  (bus_bvalid),
    .s_axil_bready  (bus_bready),
    .s_axil_bresp   (bus_bresp),
    .s_axil_arvalid (bus_arvalid),
    .s_axil_arready (bus_arready),
    .s_axil_araddr  (bus_araddr[11:0]),
    .s_axil_rvalid  (bus_rvalid),
    .s_axil_rready  (bus_rready),
    .s_axil_rdata   (bus_rdata[31:0]),
    .s_axil_rresp   (bus_rresp),
    // Interrupt
    .irq_o          (gsaf_irq)
);
```

## Step 2: Register Map

All registers are 32-bit, memory-mapped starting at the base address.

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| `0x000` | CTRL | RW | `[0]` reserved |
| `0x004` | STATUS | RO | `[0]` cmd_ready, `[1]` resp_valid, `[4+:NB]` bank_free |
| `0x008` | IRQ_STATUS | W1C | `[0]` completion, `[1]` error |
| `0x00C` | IRQ_ENABLE | RW | `[0]` completion, `[1]` error |
| `0x010` | CMD | WO | `{bank[13:12], opcode[11:8], txn_id[7:0]}` |
| `0x014` | RESP | RO | `{valid[31], status[14:12], bank[11:10], opcode[9:8], ...}` |
| `0x018` | RESP_POP | WO | Write 1: pop result, retire txn, wipe bank |
| `0x020` | PERF_CYCLES | RO | Busy cycle count |
| `0x024` | PERF_TXNS | RO | Completed transaction count |
| `0x028` | PERF_STALLS | RO | Cycles result_fifo full |
| `0x080` | RSA_P | RW | RSA-CRT prime p (64-bit) |
| `0x088` | RSA_Q | RW | RSA-CRT prime q (64-bit) |
| `0x090` | RSA_DP | RW | RSA-CRT d mod (p-1) |
| `0x098` | RSA_DQ | RW | RSA-CRT d mod (q-1) |
| `0x0A0` | RSA_QINV | RW | RSA-CRT q^-1 mod p |
| `0x100+` | Operand Banks | RW | Bank 0-3, regions A/B/M/RESULT |

## Step 3: Software Driver Example

### Basic ModExp Operation

```c
// GSAF register offsets
#define GSAF_CTRL       0x000
#define GSAF_STATUS     0x004
#define GSAF_IRQ_STATUS 0x008
#define GSAF_IRQ_ENABLE 0x00C
#define GSAF_CMD        0x010
#define GSAF_RESP       0x014
#define GSAF_RESP_POP   0x018

// Operand bank base (bank 0, region A)
#define GSAF_BANK_BASE  0x100
#define GSAF_BANK_STRIDE 0x40   // per bank
#define GSAF_REGION_STRIDE 0x10 // per region (A, B, M, RESULT)

// Opcodes
#define OP_MODEXP   0x0
#define OP_MODINV   0x1
#define OP_PQC_FWD  0xE
#define OP_PQC_INV  0xF

// Write operand to bank
void gsaf_write_operand(uint32_t base, uint32_t bank, uint32_t region,
                        const uint64_t *data, int words) {
    uint32_t addr = base + GSAF_BANK_BASE
                  + bank * GSAF_BANK_STRIDE
                  + region * GSAF_REGION_STRIDE;
    for (int i = 0; i < words; i++) {
        *(volatile uint32_t *)(addr + i*4) = (uint32_t)(data[i/2] >> (32*(i%2)));
    }
}

// Issue ModExp: base^exp mod m
int gsaf_modexp(uint32_t base, uint64_t *exp, uint64_t *mod,
                uint64_t *result, int width_words) {
    int bank = 0; // use bank 0

    // Write operands
    gsaf_write_operand(base, bank, 0, &base_val, width_words);  // A = base
    gsaf_write_operand(base, bank, 1, exp, width_words*2);       // B = exp
    gsaf_write_operand(base, bank, 2, mod, width_words);         // M = modulus

    // Wait for cmd_ready
    while (!(*(volatile uint32_t *)(base + GSAF_STATUS) & 0x1));

    // Issue command: opcode=0, bank=0, txn_id=1
    *(volatile uint32_t *)(base + GSAF_CMD) = (0 << 8) | (0 << 12) | 1;

    // Wait for response
    while (!(*(volatile uint32_t *)(base + GSAF_STATUS) & 0x2));

    // Read result
    uint32_t resp = *(volatile uint32_t *)(base + GSAF_RESP);
    uint32_t status = (resp >> 12) & 0x7;

    // Pop response (retires transaction, wipes bank)
    *(volatile uint32_t *)(base + GSAF_RESP_POP) = 1;

    return status; // 0 = OK
}
```

### Interrupt-Driven Operation

```c
// Enable completion interrupt
*(volatile uint32_t *)(GSAF_BASE + GSAF_IRQ_ENABLE) = 0x1;

// In ISR:
void gsaf_irq_handler(void) {
    uint32_t status = *(volatile uint32_t *)(GSAF_BASE + GSAF_IRQ_STATUS);
    if (status & 0x1) {
        // Completion interrupt — read result
        uint32_t resp = *(volatile uint32_t *)(GSAF_BASE + GSAF_RESP);
        // Process result...
        *(volatile uint32_t *)(GSAF_BASE + GSAF_RESP_POP) = 1;
    }
    // Clear interrupt
    *(volatile uint32_t *)(GSAF_BASE + GSAF_IRQ_STATUS) = status;
}
```

## Step 4: Timing and Area

### Estimated Resources (Yosys synthesis, WIDTH=64)

| Component | LUTs (est.) | FFs (est.) | Notes |
|-----------|------------|-----------|-------|
| ModExp engine | ~1,500 | ~1,500 | Includes 16-entry window table |
| ModInv engine | ~1,200 | ~1,200 | Bernstein-Yang divsteps |
| PQC NTT engine | ~500 | ~400 | 256-entry twiddle ROM |
| RSA-CRT engine | ~8,000 | ~7,000 | Full CRT + verification |
| ECC X25519 engine | ~3,200 | ~3,000 | 256-bit Montgomery ladder |
| Montgomery mult | ~450 | ~400 | Shared, radix-2 bit-serial |
| AXI frontend | ~300 | ~200 | Register map + IRQ |
| Scheduler + banks | ~500 | ~400 | Command dispatch + isolation |
| **Total (5 engines)** | **~15,000** | **~13,000** | **Configurable** |

### Latency (at 100 MHz)

| Operation | Latency | Throughput |
|-----------|---------|------------|
| ModExp (2048-bit) | ~320 μs | ~3.1K ops/sec |
| ModInv (2048-bit) | ~65 μs | ~15K ops/sec |
| PQC NTT (256-point) | ~130 μs | ~7.7K transforms/sec |
| RSA-CRT sign | ~650 μs | ~1.5K signatures/sec |
| ECC X25519 | ~130 μs | ~7.7K key exchanges/sec |

## Step 5: Security Considerations

### Clock Domain Crossing
- GSAF operates in a single clock domain (`clk_i`)
- If connecting to a multi-clock SoC, add a proper synchronizer on `irq_o`
- The AXI4-Lite interface is synchronous to `clk_i`

### Reset
- Active-low asynchronous reset (`rst_ni`)
- All internal state is zeroed on reset
- Operand banks are wiped on transaction retirement

### Interrupt
- Single `irq_o` output (active high)
- Level-triggered — hold until cleared via `IRQ_STATUS` W1C
- Two interrupt sources: completion and error

### Power
- Clock gating: `idle_o` signal available for ICG insertion
- No manual clock gating in RTL

## Step 6: FPGA Quick Start

For FPGA evaluation, see `fpga-guide.md`. Key points:

1. Target: Xilinx Artix-7 (xc7a35tcpg236-1)
2. Clock: 100 MHz from board oscillator
3. AXI4-Lite mapped to PMOD headers (for logic analyzer capture)
4. LEDs show `irq_o` and `idle_o` status
5. Synthesis: `vivado -mode batch -source fpga/synth-vivado.tcl`

## Step 7: Verification in SoC Context

### Integration Tests
1. **Loopback test**: Write operands → issue ModExp → read result → verify vs software
2. **Multi-engine test**: Issue ModExp and ModInv simultaneously → verify isolation
3. **Backpressure test**: Hold `resp_ready` low → verify no engine stall
4. **Interrupt test**: Enable IRQ → issue command → verify ISR fires

### Formal Properties
The fabric's SVA properties (P1-P5) verify at the interface level:
- P1: No FIFO overflow
- P2: One completion per transaction
- P3: No duplicate transaction IDs
- P4: No deadlock
- P5: Legal status encoding

These properties hold regardless of the SoC integration — they verify the fabric internally.

## Appendix: Signal Summary

| Signal | Width | Direction | Description |
|--------|-------|-----------|-------------|
| `clk_i` | 1 | in | System clock |
| `rst_ni` | 1 | in | Active-low async reset |
| `s_axil_*` | various | in/out | AXI4-Lite slave interface |
| `irq_o` | 1 | out | Interrupt (level, active high) |
| `idle_o` | 1 | out | Fabric idle (for clock gating) |
