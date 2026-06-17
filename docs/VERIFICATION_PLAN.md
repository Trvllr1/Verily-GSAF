# GSAF Verification Plan

## Three-layer strategy

| Layer | Artifact | Status |
|---|---|---|
| 1. Algorithmic | `model/golden_model.py` — bit-exact executable spec, exhaustive moduli @ W=8, randomized @ W=16/64, divstep-bound validation, **exponent/message blinding invariants** | **PASSING** (run `python model/golden_model.py`) |
| 1b. PQC algorithmic | `model/pqc_ntt_model.py` — ML-KEM (FIPS 203) + ML-DSA (FIPS 204) NTT/INTT/basemul vs schoolbook negacyclic convolution | **PASSING** (run `python model/pqc_ntt_model.py`) |
| 2. Simulation | `tb/tb_gsaf_smoke.sv` + golden-model-generated vectors (`model/gen_vectors.py`, incl. blinded-exponent vectors) through the full AXI stack | ready — needs any SV-2017 simulator |
| 3. Formal | `fv/gf_fabric_props.sv` bind file @ WIDTH=8/16, arithmetic black-boxed | ready — JasperGold / VC Formal / SymbiYosys flow |

## Formal proof obligations (fv/gf_fabric_props.sv)

- P1 — no FIFO overflow (completion queue: provable, credit-based)
- P2 — exactly one completion per transaction (state-machine containment)
- P3 — no duplicate `txn_id` in flight
- P4 — eventual forward progress / no deadlock (host fairness assumed)
- P5 — completion record integrity
- Local SVAs: multiplier constant-latency, divstep termination (`g == 0` at
  bound), engine dispatch exclusivity, FIFO under/overflow

Tool setup: black-box `gf_mont_mult` internals at full width; prove arithmetic
modules standalone at WIDTH=8 against assumes; prove fabric properties with
engines abstracted to nondet-latency valid/ready contracts.

## UVM environment (Phase 2 — scaffold spec)

Agents: AXI4-Lite master agent (active), IRQ monitor (passive),
scoreboard backed by a DPI bridge into `golden_model.py`.

Coverage mapping of the 10 mandated items:

| # | Spec item | Mechanism |
|---|---|---|
| 1 | Result FIFO backpressure | TB phase-1 periodic 50-cycle pop stalls; covergroup on `result_fifo.count` |
| 2 | Operand bank conflicts | structurally impossible — covered by *negative* assertion (frontend write-drop) + attempted-write-to-busy-bank coverpoint |
| 3 | Illegal modulus | directed vectors (m=0, m even) + constrained-random weight |
| 4 | Zero operand | directed (`0^0`, `0^e`, `inv(0)`) |
| 5 | Simultaneous ModExp + ModInv | TB phase-2; cross coverpoint `e0_busy × e1_busy` |
| 6 | Completion queue overflow | replaced by SVA proof `a_never_full_on_push` |
| 7 | Reorder buffer wraparound | seq counter wraps every 4 txns; >8-txn sequences hit it; coverpoint on `expect_q` wrap |
| 8 | Cluster reservation edge cases | back-to-back lane handshake coverpoints (req while rsp pending) |
| 9 | Host reset during execution | reset-injection sequence mid-EXP_LOOP; check clean re-arm + bank wipe |
| 10 | Maximum transaction occupancy | fill all 4 banks, submit 4 cmds, verify 4 completions; coverpoint `bank_free == 0` |

Coverage goal: 95% functional, 100% assertion, code coverage waivers
documented per block.

## Running simulation

```text
# Verilator >= 5.x
verilator --binary --timing -DGF_ASSERTIONS -f sim/gsaf.f --top tb_gsaf_smoke
./obj_dir/Vtb_gsaf_smoke

# Xcelium
xrun -sv -define GF_ASSERTIONS -f sim/gsaf.f -top tb_gsaf_smoke

# Questa
qrun -sv +define+GF_ASSERTIONS -f sim/gsaf.f -top tb_gsaf_smoke
```

Regenerate vectors after golden-model changes:

```text
python model/gen_vectors.py > tb/tb_vectors.svh
```

## TVLA leakage-assessment program (side-channel evidence)

Goal: convert "constant-time by construction" into *measured* evidence a
certification lab will accept (ISO 17825 / TVLA methodology).

1. **Platform:** FPGA eval board (Artix-7 / Zynq) with shunt-resistor power
   tap + ChipWhisperer-class capture; clock-synchronous sampling.
2. **Test sets (non-specific fixed-vs-random):**
   - ModExp: fixed exponent vs random exponents, blinding OFF — establishes
     the unprotected baseline
   - Same with exponent blinding ON (random `k` per trace) — must drop below
     |t| < 4.5 at 1M traces
   - ModInv: fixed vs random `a`
   - Cross-transaction: traces of engine A while engine B processes
     fixed-vs-random data — validates the isolation claim, not just
     per-engine hardening
3. **Timing-channel regression (pre-silicon, runs in simulation):** assert
   cycle-count equality across operand classes per engine — already encoded
   as SVA (`a_const_latency`, fixed iteration counters); any latency
   data-dependence is a CI failure, not a lab finding.
4. **Deliverable:** per-release TVLA report in the customer evidence bundle
   (traces, t-statistics, pass/fail vs ISO 17825 thresholds).

Note: power/EM leakage cannot be measured in RTL simulation; items 1-2 and 4
require the FPGA eval kit (GTM productization item 4). Item 3 is active now.
