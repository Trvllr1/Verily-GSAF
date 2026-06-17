# Chassis Evidence Pack

## Contents

This folder contains verification evidence for the GSAF chassis (the scheduler, frontend, operand banks, completion queue, reorder buffer, and fabric top).

### RTL Snapshot
Frozen copy of all 14 SystemVerilog modules used for this evidence pack.

### Formal Verification
SymbiYosys proof results for fabric-level properties:
- P1: No FIFO overflow
- P2: Exactly one completion per transaction
- P3: No duplicate txn_id in flight
- P4: No deadlock / eventual forward progress
- P5: Completion record integrity

### Simulation
cocotb test results (JUnit XML) from the full-stack smoke test.

### Golden Model
Output of the Python golden model self-tests, verifying algorithmic correctness.

## Evidence Validity

This evidence is valid for any engine that implements `gf_engine_if.sv`. The chassis was verified against the formal interface specification, not against any specific engine implementation.

## Regeneration

```bash
make evidence
```
