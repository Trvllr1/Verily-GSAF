# Engine SDK Developer Guide

## Overview

This guide explains how to build custom engines for the GSAF fabric. Custom engines implement the `gf_engine_if.sv` interface and can be validated, verified, and packaged using GSAF Studio tools.

## Architecture

```
Client Engine ────── gf_engine_if.sv ────── GSAF Chassis
                     (formal contract)
```

The engine interface defines:
- **Command channel**: valid/ready handshake with opcode, operands, modulus
- **Result channel**: valid/ready handshake with result, status, txn_id
- **Engine status**: idle signal for backpressure immunity

## Quick Start

### 1. Generate Engine Template

```bash
gsaf template my_engine --width 64
# Creates: rtl/my_engine.sv
```

### 2. Implement Your Computation

Edit `rtl/my_engine.sv` and replace the placeholder logic in the `S_COMPUTE` state:

```systemverilog
S_COMPUTE: begin
  cnt_q <= cnt_q + 1'b1;
  
  // Your constant-time computation here
  // MUST have fixed latency (no data-dependent branches)
  if (cnt_q == CNT_W'(COMPUTE_CYCLES - 1)) begin
    result_q <= your_computation(a_q, b_q, m_q);
    state_q  <= S_DONE;
  end
end
```

### 3. Create Golden Model

Write a Python golden model that mirrors your hardware computation:

```python
def my_computation(a, b, m, width):
    # Bit-exact algorithmic specification
    # Use ONLY shifts, adds, subtracts, compares, muxes
    # No '*', '//', '%' on secret data
    result = 0
    for i in range(width):
        # Your algorithm here
        pass
    return result
```

### 4. Validate Your Engine

```bash
gsaf validate-engine rtl/my_engine.sv -g model/my_model.py
```

This runs:
1. Verilator lint (interface compliance)
2. Yosys synthesis (resource check)
3. SymbiYosys formal proof (constant-time)
4. cocotb simulation (functional correctness)
5. Evidence pack generation

## Interface Contract

### Command Channel

| Signal | Direction | Description |
|--------|-----------|-------------|
| `cmd_valid` | chassis → engine | Command valid |
| `cmd_ready` | engine → chassis | Engine ready to accept |
| `cmd_opcode` | chassis → engine | Operation code |
| `cmd_txn_id` | chassis → engine | Transaction ID |
| `cmd_base` | chassis → engine | Primary operand |
| `cmd_exp` | chassis → engine | Secondary operand |
| `cmd_m` | chassis → engine | Modulus |

### Result Channel

| Signal | Direction | Description |
|--------|-----------|-------------|
| `rsp_valid` | engine → chassis | Result valid |
| `rsp_ready` | chassis → engine | Chassis ready to accept |
| `rsp_result` | engine → chassis | Computed result |
| `rsp_status` | engine → chassis | Status code |
| `rsp_txn_id` | engine → chassis | Transaction ID (echoed) |

### Status Codes

| Code | Name | Description |
|------|------|-------------|
| 0 | STATUS_OK | Operation completed successfully |
| 1 | STATUS_INVALID_INPUT | Modulus==0, modulus even, operand >= modulus |
| 2 | STATUS_NOT_INVERTIBLE | gcd(a, m) != 1 (ModInv only) |
| 3 | STATUS_UNSUPPORTED | Reserved opcode |
| 7 | STATUS_FAULT | Internal consistency check failed |

## Security Requirements

### 1. Constant-Time

- **Fixed latency**: Your engine MUST complete in a bounded number of cycles that depends only on WIDTH, never on operand values.
- **No data branches**: All computation paths must be executed regardless of operand values.
- **Unconditional operations**: Compute both branches of any conditional and mux the result.

### 2. No Silent Faults

- **Result range checks**: Verify output is within expected bounds.
- **Status reporting**: Report STATUS_FAULT for any internal error.
- **No silent corruption**: Never return a wrong answer without flagging it.

### 3. Secure Wipe

- **Operand registers**: Zero out all operand registers on retirement.
- **Intermediate state**: Clear any intermediate computation state.
- **Key material**: Treat operands as key material.

## Verification

### Formal Properties

Your engine should satisfy these SVA properties:

```systemverilog
// P_E1: Eventual response
(cmd_valid && cmd_ready) |-> s_eventually (rsp_valid && rsp_ready);

// P_E2: Legal status
(rsp_valid && rsp_ready) |-> rsp_status inside {0,1,2,3,7};

// P_E3: Backpressure immunity
(cmd_valid && cmd_ready && !engine_idle) |-> s_eventually rsp_valid;

// P_E4: One at a time
(cmd_valid && cmd_ready) |=>
  !cmd_valid until_with (rsp_valid && rsp_ready);
```

### Simulation Tests

Create cocotb tests that verify:
1. Basic functionality vs golden model
2. Edge cases (zero, max, identity)
3. Error paths (invalid inputs)
4. Backpressure tolerance

## Evidence Pack

When validated, your engine generates an evidence pack:

```
evidence-pack/02_engine_<name>/
├── rtl/
│   └── <name>.sv           # Your engine RTL
├── formal/
│   └── results/            # Formal proof results
├── dyno/
│   └── results.xml         # cocotb test results
└── README.md               # Evidence narrative
```

This evidence pack is what clients receive when they license your engine.

## Example Engines

### ModExp Engine
- **Opcode**: OP_MODEXP (0x0)
- **Computation**: Fixed-window modular exponentiation
- **Latency**: 2·WIDTH doublings + (16 + 5·WIDTH/4 + 2) multiplies
- **Countermeasure**: Exponent blinding (DPA)

### ModInv Engine
- **Opcode**: OP_MODINV (0x1)
- **Computation**: Bernstein-Yang divsteps
- **Latency**: DIVSTEP_BOUND iterations + 2 cycles
- **Countermeasure**: Sparse FSM encoding (fault detection)

### PQC NTT Engine
- **Opcode**: OP_PQC_FWD_NTT (0xE) / OP_PQC_INV_NTT (0xF)
- **Computation**: Cooley-Tukey / Gentleman-Sande NTT
- **Latency**: 8 layers × 128 butterflies
- **Countermeasure**: NTT is naturally constant-time
