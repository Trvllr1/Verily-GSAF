# ModInv Engine Evidence Pack

## Contents

This folder contains verification evidence for the `gf_modinv_engine` (Bernstein-Yang constant-time modular inverse).

### Dyno Test Results
cocotb test results from the isolated engine test harness (`dyno_modinv.py`).

### Formal Verification
Constant-time proof: the engine completes in exactly DIVSTEP_BOUND iterations for all inputs.

## Evidence Validity

This evidence is specific to the ModInv engine. To use a different engine, replace this entire folder with the new engine's evidence pack.

## Regeneration

```bash
cd tb/dynos && make test-modinv
```
