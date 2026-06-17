# Verification Plan

## Three-Layer Strategy

| Layer | Artifact | Status |
|-------|----------|--------|
| 1. Algorithmic | `model/golden_model.py` — bit-exact executable spec | PASSING |
| 1b. PQC algorithmic | `model/pqc_ntt_model.py` — ML-KEM/ML-DSA NTT | PASSING |
| 2. Simulation | `tb/` — cocotb + SystemVerilog testbenches | Ready |
| 3. Formal | `fv/` + `formal/` — SVA properties + SymbiYosys | Ready |

## Formal Proof Obligations

| Property | Description | Status |
|----------|-------------|--------|
| P1 | No FIFO overflow | Provable (credit-based) |
| P2 | Exactly one completion per transaction | State-machine containment |
| P3 | No duplicate txn_id in flight | Structural invariant |
| P4 | No deadlock / eventual forward progress | Host fairness assumed |
| P5 | Completion record integrity | Legal status encoding |

## Security Countermeasures

### Shipped in V5.1
1. **Exponent blinding (DPA)**: EXP_W = WIDTH + EXP_BLIND_BITS
2. **Message blinding (DPA)**: Host-side blind/unblind flow
3. **Fault detection**: Sparse FSM encodings + result range checks

### Roadmap
1. TVLA leakage campaign on FPGA
2. First-order masking evaluation
3. RSA-CRT engine with Bellcore-attack hardening
4. PQC engines (ML-KEM/ML-DSA)

## Running Verification

```bash
# Golden model
python model/golden_model.py
python model/pqc_ntt_model.py

# Simulation
make sim

# Formal
make formal
make formal-engine
```
