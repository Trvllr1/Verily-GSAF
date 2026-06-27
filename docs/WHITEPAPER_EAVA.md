# Whitepaper 1: The EAVA Methodology

## A Framework for Pre-Silicon Hardware IP Verification

**Verily | 2026**

---

## Abstract

The hardware IP verification industry faces a crisis of confidence. Customers spend millions on IP cores but receive little evidence that the silicon will behave as specified. Formal verification, when used, produces results that only experts can interpret. Simulation coverage metrics tell you what was tested, not what was proven. The result: certification timelines stretch to 18+ months, and security vulnerabilities slip through to production silicon.

This paper introduces **EAVA** (Explore → Architect → Verify → Assure), a structured methodology for pre-silicon hardware IP verification that addresses these industry pain points. EAVA is the foundational workflow of GSAF Studio, Verily's pre-silicon verification platform for cryptographic IP cores.

---

## 1. The Industry Problem

### 1.1 The Verification Gap

Hardware IP verification today suffers from three systemic failures:

**The Evidence Gap.** IP vendors ship RTL and claim security properties. Customers must independently verify these claims. The verification evidence — formal proofs, simulation results, test vectors — is either not shipped or requires custom engagement to obtain.

**The Certification Gap.** FIPS 140-3 and Common Criteria evaluations require extensive documentation and testing. IP vendors provide minimal support, leaving customers to reconstruct evidence from scratch. A single FIPS evaluation can take 12-18 months and cost $500K-$2M.

**The PQC Gap.** NIST's post-quantum standards (FIPS 203, 204) force every secure element, HSM, and smart-NIC vendor to re-spin crypto silicon by 2027-2030. Most IP vendors are still on roadmaps. Customers face an impossible choice: wait for PQC-ready IP or build custom solutions.

### 1.2 Why Current Approaches Fail

| Approach | What It Proves | What It Misses |
|----------|---------------|----------------|
| Simulation (UVM) | Functional correctness for tested vectors | Corner cases, security properties, timing leakage |
| Formal verification | Mathematical proof of properties | Only properties you think to specify |
| Code coverage | What lines were exercised | Whether those lines matter |
| Static linting | Syntactic correctness | Semantic correctness |

The fundamental issue: **testing shows the presence of bugs, not their absence.** For security-critical hardware, this is insufficient.

---

## 2. The EAVA Methodology

EAVA is a four-phase methodology that transforms hardware IP verification from an ad-hoc process into a structured, evidence-generating workflow.

### Phase 1: EXPLORE

**Goal:** Understand the design space, constraints, and threat model before writing a single line of RTL.

**Activities:**
- Define the cryptographic algorithm specification
- Identify security properties (constant-time, fault resistance, DPA countermeasures)
- Map the threat model (who attacks, what they gain, what resources they have)
- Define the verification strategy (formal vs. simulation vs. hybrid)
- Identify certification requirements (FIPS, CC, TVLA)

**GSAF Studio Implementation:**
- `gsaf explore` — Scans RTL modules, identifies interfaces, reports formal verification status
- `gsaf architect` — Validates architectural constraints (WIDTH, bank count, multiplier lanes)

**Industry Pain Addressed:** Most IP projects skip or rush the exploration phase. Engineers jump to implementation without a clear verification strategy. EAVA forces this upfront investment, which pays dividends throughout the lifecycle.

### Phase 2: ARCHITECT

**Goal:** Design the verification infrastructure that will generate evidence throughout development.

**Activities:**
- Define the formal property specification (SVA assertions)
- Design the golden model (bit-exact algorithmic specification)
- Create the test harness architecture (dyno testbenches)
- Plan the evidence pack structure (what artifacts, what format, what signing)
- Define the integration contract (engine interface spec)

**GSAF Studio Implementation:**
- `gsaf template` — Generates engine template with formal interface contract
- `gsaf validate-engine` — Runs 5-step validation pipeline (lint → synthesis → formal → simulation → evidence)

**Industry Pain Addressed:** Verification infrastructure is typically an afterthought. Engineers write tests after implementation, leading to gaps. EAVA requires verification architecture to precede implementation.

### Phase 3: VERIFY

**Goal:** Execute the verification strategy and collect evidence.

**Activities:**
- Run formal property proofs (SymbiYosys)
- Execute simulation tests (cocotb)
- Cross-check against golden models (Python)
- Collect coverage metrics
- Generate signed evidence bundles

**GSAF Studio Implementation:**
- `gsaf verify` — Orchestrates golden models, lint, formal, and simulation
- `gsaf assure` — Generates tiered evidence packs with HMAC-SHA256 signing

**Industry Pain Addressed:** Verification evidence is scattered across tools, formats, and locations. EAVA centralizes evidence collection into structured, signed bundles that ship with the IP.

### Phase 4: ASSURE

**Goal:** Package evidence for customer delivery and certification.

**Activities:**
- Generate evidence packs (free/paid/enterprise tiers)
- Sign manifests with tamper-evident HMAC
- Create customer-facing documentation
- Prepare certification submission packages
- Establish ongoing verification regression

**GSAF Studio Implementation:**
- `gsaf assure --tier paid` — Generates complete evidence pack
- License server — Issues, validates, revokes license tokens
- CLI tooling — Full pipeline from exploration to delivery

**Industry Pain Addressed:** Certification evidence is typically assembled manually for each customer. EAVA automates evidence generation, making it a continuous process rather than a one-time event.

---

## 3. EAVA in Practice: GSAF Case Study

### 3.1 The CryptoKast Chassis Verification

The CryptoKast chassis (scheduler, transaction table, operand banks, completion queue) was verified using EAVA:

**Explore:** Defined 5 formal properties (P1-P5) covering FIFO overflow, completion integrity, transaction uniqueness, deadlock freedom, and status encoding.

**Architect:** Designed the `gf_engine_if.sv` interface contract with 5 SVA properties (P_E1 through P_E5) that prove engine-chassis interaction correctness.

**Verify:** Ran SymbiYosys proofs on all 5 properties. Cross-checked with cocotb simulation of the full fabric.

**Assure:** Generated evidence pack with formal proof results, simulation logs, and golden model output.

**Result:** The chassis has been verified against its specification with mathematical proof, not just testing.

### 3.2 The PQC Engine Verification (PiQ / SaV)

The PQC NTT engines were verified using EAVA:

**Explore:** Identified the NTT butterfly as a modular multiply-accumulate — the same resource class as the Montgomery multiplier. Mapped FIPS 203/204 requirements for PiQ (ML-KEM) and SaV (ML-DSA).

**Architect:** Created `pqc_ntt_model.py` with schoolbook cross-check. Defined constant-time properties (fixed iteration count, no data-dependent branches).

**Verify:** Golden model passes 10 NTT round-trips + polymuls vs schoolbook for both ML-KEM and ML-DSA. cocotb tests pass 4/4. RTL compiles clean with zero CDC warnings.

**Assure:** Evidence pack includes golden model output, simulation results, and RTL snapshot.

**Result:** PiQ and SaV engines are verified against FIPS 203/204 with machine-checked evidence.

---

## 4. EAVA vs. Traditional Verification

| Dimension | Traditional | EAVA |
|-----------|------------|------|
| Verification timing | After implementation | Before + during + after |
| Evidence generation | Manual, ad-hoc | Automated, structured |
| Proof approach | Testing (shows presence) | Formal + testing (proves absence) |
| Certification prep | Assembled per customer | Continuous, shippable |
| PQC readiness | Roadmap | Production-ready |
| Cost model | High NRE per engagement | Fixed tooling + per-license |

---

## 5. The Business Case for EAVA

### 5.1 Cost of Verification Failure

| Failure Mode | Cost | Timeline Impact |
|-------------|------|-----------------|
| Security vulnerability found post-silicon | $1M-$10M (respins) | 6-12 months |
| FIPS evaluation fails | $500K-$2M | 12-18 months |
| TVLA side-channel detected | $200K-$500K | 6-12 months |
| PQC migration delay | Market share loss | 2-3 years |

### 5.2 EAVA ROI

| Benefit | Quantified Value |
|---------|-----------------|
| Certification timeline reduction | 3-6 months saved |
| Evidence assembly automation | 40-60 hours saved per customer |
| Formal proof confidence | Eliminates post-silicon respins |
| PQC readiness | 1-2 year competitive advantage |

---

## 6. Conclusion

EAVA is not just a verification methodology — it's a business strategy. By structuring verification as a continuous, evidence-generating process, EAVA transforms IP delivery from a transaction into a partnership. Customers receive not just RTL, but the mathematical proof that it works.

The hardware IP industry is at an inflection point. Post-quantum deadlines, certification requirements, and security threats demand a new approach to verification. EAVA provides that approach.

---

## References

1. NIST FIPS 140-3: Security Requirements for Cryptographic Modules
2. NIST FIPS 203: Module-Lattice-Based Key-Encapsulation Mechanism Standard
3. NIST FIPS 204: Module-Lattice-Based Digital Signature Standard
4. Common Criteria Part 1-3: Evaluation Methodology for IT Security
5. ISO 17825: Testing methods for side-channel countermeasures
6. GSAF Architecture Specification V5.1 (Verily, 2026)
7. GSAF Verification Plan (Verily, 2026)
