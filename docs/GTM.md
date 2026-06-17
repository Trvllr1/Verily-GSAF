# GreenField Secure Arithmetic Fabric — Go-To-Market Brief

## Positioning

**"The formally verified post-quantum transition fabric."**

Lead message: every security chip must run classical (RSA/ECC) *and*
quantum-safe (ML-KEM/ML-DSA) crypto side by side through the 2027-2035
transition. GSAF is the chassis built for exactly that: one scheduler, one
isolation model, one proof story — engines plug in per customer. The PQC
engine math (NTT for both FIPS 203 and FIPS 204) is already modeled and
machine-verified in `model/pqc_ntt_model.py`; the butterfly unit maps onto
the same reserved-lane resource class as the Montgomery multipliers, so the
verified fabric does not change when PQC engines land.

Do not sell "a modexp accelerator" — that market is owned by Rambus, Synopsys
DWC, and free OpenTitan BigNum. Sell the thing they don't ship: **evidence**.
Every license includes the proof bundle (SVA results, golden-model
equivalence, constant-time latency proofs, TVLA leakage reports) that a
licensee's security certification team would otherwise spend quarters
reconstructing.

## Wedge and timing

1. **PQC migration deadlines** (NIST / CNSA 2.0) are forcing every secure
   element, HSM, smart-NIC and automotive ECU vendor to re-spin crypto
   silicon by 2027–2030. They must carry classical RSA/ECC *alongside* ML-KEM
   /ML-DSA during the transition.
2. GSAF's multi-engine fabric with reserved engine slots is exactly the
   chassis for hybrid classical+PQC parts: one scheduler, one isolation
   model, one verification story, engines added per customer.
3. Automotive (ISO 21434) and FIPS 140-3 level 3+ buyers pay a premium for
   deterministic-latency, evidence-backed IP.

## Target customers (in order)

| Segment | Why they buy | Entry product |
|---|---|---|
| Secure element / smartcard vendors | cert evidence cuts CC EAL timeline | RSA/ECC fabric + proof bundle |
| DPU / smart-NIC teams | per-tenant *transaction isolation* story (multi-engine, no cross-txn timing observability) | OOO fabric @ NUM_MULTIPLIERS=8 |
| Automotive HSM | deterministic latency + ISO 21434 collateral | in-order fabric, lockstep option |
| PQC-transition ASIC programs | hybrid chassis, engines on demand | fabric license + PQC engine NRE |

## Deliverables ladder

**Today (this repo):**
- Synthesizable RTL (SV-2017), zero `*`/`/`/`%` datapaths, tool-CG ready
- **DPA countermeasures shipped:** exponent-blinding hardware support
  (EXP_BLIND_BITS wide exponent path) + message-blinding host flow, both
  machine-verified in the golden model
- **Fault countermeasures shipped:** sparse FSM encodings with fault traps,
  runtime result range checks, divstep termination check → `STATUS_FAULT`
  (never a silent wrong answer)
- **PQC arithmetic golden model:** ML-KEM (FIPS 203) and ML-DSA (FIPS 204)
  NTT/INTT/basemul, verified against schoolbook negacyclic convolution
- Executable golden model with self-proof (`model/golden_model.py` — passing)
- Vector-driven full-stack smoke TB + formal property bind file
- Architecture / verification / integration docs

**Productization (next 2 quarters):**
1. **gf_pqc_engine RTL** (NTT butterfly array on a reserved lane) — the
   headline roadmap item; golden model already proves the math
2. Radix-4 CSA multiplier (≈4× throughput) behind the same lane interface
3. UVM environment to 95% functional coverage; nightly regression
4. FPGA eval kit: Artix/Zynq bitstream + Linux driver + benchmark suite
5. TVLA leakage campaign on FPGA captures (program defined in
   VERIFICATION_PLAN.md) — converts "constant-time by construction" into
   measured evidence
6. PPA report: 2048/4096-bit points on N7/N12/22FDX + FPGA LUT counts

**Certification pack (revenue multiplier):**
- FIPS 140-3 algorithm certs (CAVP) for ModExp/ModInv primitives
- Common Criteria support documentation
- Safety/security manual, threat model, TVLA evidence

## Pricing model

- Per-design license + royalty (standard silicon IP)
- Proof bundle + cert pack as attach (high margin, near-zero COGS)
- PQC engine NRE per customer, folding back into the catalog

## Honest risk register

| Risk | Mitigation |
|---|---|
| Crowded classical-crypto IP market | lead with proofs + PQC chassis, not modexp specs |
| Power side channels: blinding shipped, but lab evidence pending | TVLA capture campaign on FPGA eval kit before "production-intent" marketing |
| Throughput vs incumbents (radix-2 v1) | radix-4 upgrade is interface-compatible; sell determinism first |
| Single-source startup risk for buyers | escrow + full verification artifact delivery reduces lock-in fear |
