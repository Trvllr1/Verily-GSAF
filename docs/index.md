# GSAF Studio

**The formally verified post-quantum transition fabric.**

GSAF (GreenField Secure Arithmetic Fabric) is a production-intent constant-time cryptographic arithmetic fabric with synthesizable SystemVerilog-2017 modules, executable golden models, and a complete verification evidence pack.

## Features

- **Constant-time by construction**: Every operation's latency depends only on `WIDTH`, never on operand values
- **Formal verification**: SVA properties prove no FIFO overflow, exactly one completion per transaction, no deadlock
- **DPA countermeasures**: Exponent blinding + message blinding, machine-verified in golden model
- **Fault detection**: Sparse FSM encodings + runtime result checks — no silent wrong answers
- **Modular verification**: Each engine verified on its own "dyno" test harness

## Quick Start

```bash
# Clone the repository
git clone https://github.com/Trvllr1/Verily-GSAF.git
cd Verily-GSAF

# Verify the golden model (no EDA tools needed)
python model/golden_model.py
python model/pqc_ntt_model.py

# Run simulation
make sim

# Run formal verification
make formal
```

## Documentation

- [Architecture](ARCHITECTURE.md) — V5.1 microarchitecture spec
- [Verification Plan](VERIFICATION.md) — Three-layer verification strategy
- [Getting Started](getting-started.md) — Installation and setup guide
- [CLI Reference](cli.md) — GSAF Studio CLI commands
- [Evidence Packs](evidence.md) — Understanding the evidence bundle
