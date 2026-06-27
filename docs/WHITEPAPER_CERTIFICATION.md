# Whitepaper 2: The Certification Gap

## Why Hardware IP Verification Fails at the Certification Boundary

**Verily | 2026**

---

## Abstract

Hardware IP certification — FIPS 140-3, Common Criteria, TVLA side-channel testing — is the final gate between IP delivery and production deployment. Yet the certification process remains opaque, expensive, and slow. IP vendors ship RTL with minimal evidence. Customers spend months reconstructing what the vendor should have proven. This paper analyzes the certification gap, quantifies its cost, and presents GSAF's approach to closing it.

---

## 1. The Certification Landscape

### 1.1 FIPS 140-3

The Federal Information Processing Standard for cryptographic modules requires:

| Requirement | What It Means | GSAF Status |
|-------------|---------------|-------------|
| Algorithm certification (CAVP) | Each algorithm must pass NIST test vectors | SAFMex/SAFInv: ready. PiQ/SaV: ready. AES/SHA: not implemented |
| Module security policy | Documented security claims | Partially documented |
| Self-tests | Power-on and conditional tests | Golden model self-tests pass |
| Key management | Lifecycle documentation | License server provides audit trail |
| Physical security | Tamper resistance | Customer responsibility (IP core) |
| Design assurance | Development process documentation | CI/CD pipeline, formal verification |

### 1.2 Common Criteria

CC EAL2+ requires:

| Component | What It Means | GSAF Status |
|-----------|---------------|-------------|
| Security Target (ST) | Formal security claims | Not written |
| Functional specification | Interface documentation | Complete |
| Design representation | Internal design docs | Complete (ARCHITECTURE.md) |
| Testing evidence | Test results + coverage | cocotb results available |
| Vulnerability analysis | Known weaknesses | Partial |
| Delivery procedures | How IP is shipped | Not documented |

### 1.3 TVLA Side-Channel Testing

ISO 17825 requires:

| Requirement | What It Means | GSAF Status |
|-------------|---------------|-------------|
| Test methodology | Fixed vs random input comparison | Defined in VERIFICATION_PLAN.md |
| Hardware platform | FPGA + power analysis | Not available (pre-silicon) |
| Leakage assessment | Statistical t-test results | Not captured |
| Countermeasure evaluation | DPA/fault effectiveness | RTL shipped, lab evidence pending |

---

## 2. The Certification Cost Problem

### 2.1 Direct Costs

| Item | Low Estimate | High Estimate |
|------|-------------|---------------|
| CAVP testing (per algorithm) | $15,000 | $30,000 |
| CC EAL2+ evaluation | $100,000 | $200,000 |
| TVLA lab testing | $20,000 | $40,000 |
| Documentation preparation | $30,000 | $50,000 |
| **Total per IP block** | **$165,000** | **$320,000** |

### 2.2 Indirect Costs

| Item | Cost | Notes |
|------|------|-------|
| Engineering time for documentation | $50,000-$100,000 | 3-6 months of senior engineer time |
| Certification timeline delay | $200,000-$500,000 | Opportunity cost of delayed market entry |
| Re-spins if certification fails | $1,000,000-$10,000,000 | Physical silicon respins |
| Customer integration delays | $100,000-$300,000 | Per customer, per engagement |

### 2.3 The Evidence Assembly Problem

The largest hidden cost is **evidence assembly**. When a customer evaluates IP for certification, they need:

1. Formal proof results (SVA properties, proof scripts)
2. Simulation test results (coverage metrics, pass/fail)
3. Golden model equivalence proofs
4. Constant-time analysis documentation
5. Side-channel countermeasure documentation
6. Design assurance records
7. Delivery procedure documentation

**Without EAVA:** Each customer engagement requires custom evidence assembly. The IP vendor's engineering team spends 2-4 weeks per customer reconstructing evidence from scattered tools and formats.

**With EAVA:** Evidence is continuously generated, signed, and packaged. Customer delivery is automated — `gsaf assure --tier paid` produces a complete evidence bundle in minutes.

---

## 3. Why Certification Fails

### 3.1 Root Cause Analysis

| Root Cause | Frequency | Impact |
|-----------|-----------|--------|
| Insufficient formal verification | 40% | Evidence gaps require expensive re-verification |
| Missing side-channel evidence | 30% | TVLA failure, silicon respin |
| Incomplete documentation | 20% | CC evaluation delays |
| Algorithm implementation errors | 10% | CAVP failure, algorithm re-implementation |

### 3.2 The "Claim vs. Proof" Problem

Most IP vendors **claim** security properties without **proving** them:

| Property | Typical Vendor Claim | GSAF Approach |
|----------|---------------------|---------------|
| "Constant-time" | Marketing statement | Formal SVA property + machine-checked proof |
| "DPA-resistant" | "We use blinding" | Golden model invariant + exponent blinding verification |
| "Fault-tolerant" | "We have checks" | Sparse FSM encoding + result range check + STATUS_FAULT |
| "PQC-ready" | "On our roadmap" | ML-KEM/ML-DSA NTT shipped, golden model verified |

### 3.3 The PQC Certification Challenge

PQC adds unique certification complexity:

1. **New algorithms** — CAVP test suites for FIPS 203/204 are still being finalized
2. **Hybrid mode** — Classical + PQC running simultaneously requires joint certification
3. **Performance requirements** — PQC operations are computationally expensive
4. **Implementation diversity** — Different NTT architectures produce different side-channel profiles

GSAF addresses this by shipping PiQ, SaV, and Compo with the same verification evidence as classical engines (SAFMex, SAFInv, Didym, Oxym) — golden model equivalence, formal properties, and cocotb test results.

---

## 4. GSAF's Certification Strategy

### 4.1 Evidence-First Architecture

GSAF was designed for certification from day one:

| Design Decision | Certification Benefit |
|----------------|----------------------|
| Golden model self-tests | CAVP algorithm validation ready |
| Formal SVA properties | CC design assurance evidence |
| Signed evidence packs | Tamper-evident delivery for labs |
| Tiered evidence structure | Matches certification levels |
| CLI tooling | Automated evidence generation |

### 4.2 The Evidence Pack System

```
evidence-pack/
├── 01_crypto_kast/      # CryptoKast chassis verification evidence
│   ├── rtl/             # Frozen RTL snapshot
│   ├── formal/          # SVA proof results
│   ├── simulation/      # cocotb test results
│   └── golden_model/    # Model output + self-test results
├── 02_engine_modexp/    # Per-engine evidence
├── 02_engine_modinv/
├── 02_engine_pqc/
├── 02_engine_rsa_crt/
└── 02_engine_ecc/
```

Each pack is HMAC-SHA256 signed. Labs can verify integrity without trusting the delivery channel.

### 4.3 Certification Roadmap

| Phase | Timeline | Deliverable |
|-------|----------|-------------|
| Evidence collection | Now | Golden models, cocotb tests, formal properties |
| CAVP engagement | Q1 2027 | Algorithm certificates for SAFMex/SAFInv/Oxym |
| CC documentation | Q2 2027 | Security Target, design docs, test results |
| CC evaluation | Q3 2027 | EAL2+ certificate |
| TVLA capture | Q4 2026 | FPGA-based side-channel evidence |
| Certification pack | Q4 2027 | Bundled evidence for customer delivery |

---

## 5. The Business Impact

### 5.1 Customer Value Proposition

| Without GSAF Evidence | With GSAF Evidence |
|----------------------|-------------------|
| 12-18 months certification | 6-12 months certification |
| $500K-$2M certification cost | $200K-$400K certification cost |
| Custom evidence assembly per customer | Automated evidence delivery |
| Risk of post-silicon respin | Formal proof reduces respin risk |

### 5.2 Revenue Model

| Product | Price | What It Includes |
|---------|-------|-----------------|
| IP License | $75K-$500K | RTL + golden models + evidence pack |
| Certification Pack | $100K-$200K | CAVP evidence + CC documentation + TVLA report |
| Ongoing Maintenance | 15-20% of license/year | Updates + re-certification support |

### 5.3 Market Timing

The PQC transition (2027-2035) creates a window where:
- Every secure element vendor needs PQC-ready IP
- Certification timelines are critical (market window = 2-3 years)
- Evidence bundles save months of engineering time

GSAF's certification-ready evidence positions it as the fastest path to PQC-compliant silicon.

---

## 6. Conclusion

The certification gap is not a technical problem — it's an evidence problem. IP vendors ship RTL without evidence. Customers spend months assembling what should have been included. EAVA and the evidence pack system close this gap by making evidence generation continuous, automated, and tamper-evident.

The cost of certification failure is measured in millions of dollars and years of delay. The cost of certification readiness is measured in tooling and process — a fraction of the failure cost.

---

## References

1. NIST FIPS 140-3: Security Requirements for Cryptographic Modules
2. Common Criteria Part 1-3: Evaluation Methodology
3. ISO 17825: Testing methods for side-channel countermeasures
4. GSAF Verification Plan V5.1
5. GSAF Certification Gap Analysis (Verily, 2026)
