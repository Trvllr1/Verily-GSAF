# ModExp Engine Evidence Pack

## Contents

This folder contains verification evidence for the `gf_modexp_engine` (fixed-window constant-time modular exponentiation).

### Dyno Test Results
cocotb test results from the isolated engine test harness (`dyno_modexp.py`).

### Formal Verification
Constant-time proof: the engine completes in a bounded number of cycles that depends only on WIDTH and EXP_W, never on operand values.

## Evidence Validity

This evidence is specific to the ModExp engine. To use a different engine, replace this entire folder with the new engine's evidence pack.

## Regeneration

```bash
cd tb/dynos && make test-modexp
```
