# GreenField Secure Arithmetic Fabric™ (GSAF)

Production-intent constant-time cryptographic arithmetic fabric — V5.1 RTL,
executable golden models (classical + PQC), DPA/fault countermeasures, formal
properties, and GTM collateral.

## Features

- **Constant-time by construction**: Every operation's latency depends only on `WIDTH`
- **Formal verification**: SVA properties prove safety invariants
- **DPA countermeasures**: Exponent + message blinding, machine-verified
- **Fault detection**: Sparse FSM encodings + runtime checks — no silent wrong answers
- **Evidence packs**: Structured verification artifacts for certification

## Project Structure

```
Verily-GSAF/
├── rtl/              # Synthesizable SystemVerilog-2017
│   ├── gf_pkg.sv                 types, opcodes, proof-derived divstep bound
│   ├── gf_secure_fabric_top.sv   top level
│   ├── gf_axil_frontend.sv       AXI4-Lite regmap + IRQ + perf counters
│   ├── gf_scheduler.sv           dispatch, input screening, completion collect
│   ├── gf_modexp_engine.sv       fixed-window constant-time modexp
│   ├── gf_modinv_engine.sv       Bernstein-Yang divstep modinv
│   ├── gf_mont_mult.sv           radix-2 Montgomery multiplier (W+2 cycles)
│   └── ...                       (14 modules total)
├── model/            # Python golden models (bit-exact algorithmic specs)
│   ├── golden_model.py           classical + blinding invariants; self-testing
│   ├── pqc_ntt_model.py          ML-KEM (FIPS 203) / ML-DSA (FIPS 204) NTT
│   └── gen_vectors.py            emits tb/tb_vectors.svh
├── tb/               # Testbenches (cocotb + SystemVerilog)
├── fv/               # Formal property bind file
├── formal/           # SymbiYosys proof scripts
├── sim/              # Simulation filelists
├── docs/             # Documentation (MkDocs)
└── evidence-pack/    # Generated verification evidence
```

## Quick Start

```bash
# 1. Prove the algorithms (no EDA tools needed)
python model/golden_model.py     # classical arithmetic + blinding invariants
python model/pqc_ntt_model.py    # ML-KEM / ML-DSA NTT math

# 2. Check toolchain
make check-tools

# 3. Run simulation
make sim

# 4. Run formal verification
make formal

# 5. Generate evidence pack
make evidence
```

## Toolchain

| Tool | Purpose | Version |
|------|---------|---------|
| Verilator | Simulation | 5.048 |
| Icarus Verilog | Simulation | 13.0 |
| Yosys | Synthesis | 0.56 |
| SymbiYosys | Formal | 0.66 |
| cocotb | Testbench | 2.0 |
| MkDocs | Documentation | Latest |

## Architectural Invariants

- **Constant time:** every operation's latency is a function of `WIDTH` only
- **Transaction isolation:** one operand bank per transaction, statically owned
- **No arbitration on secret-dependent paths:** multiplier lanes hard-wired
- **Backpressure firewall:** host stalls never reach arithmetic pipelines
- **DPA hardening:** exponent path WIDTH + EXP_BLIND_BITS bits wide
- **Fault detection:** glitch-trap FSM encodings + runtime result checks

## Documentation

- [Architecture](docs/ARCHITECTURE.md) — V5.1 microarchitecture spec
- [Verification Plan](docs/VERIFICATION.md) — Three-layer verification strategy
- [Getting Started](docs/getting-started.md) — Installation guide
- [CLI Reference](docs/cli.md) — GSAF Studio CLI commands
- [Evidence Packs](docs/evidence.md) — Understanding the evidence bundle

## License

Copyright (c) 2026 Verily. All rights reserved.
