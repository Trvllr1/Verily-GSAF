# GSAF Technical Sales Deck

## Slide 1: Title

**GreenField Secure Arithmetic Fabric (GSAF)**
*The Formally Verified Post-Quantum Transition Fabric*

Verily | 2026

---

## Slide 2: The Problem

Every security chip must run classical (RSA/ECC) **and** quantum-safe (ML-KEM/ML-DSA) crypto side by side through the 2027-2035 transition.

**Current state:**
- Separate IP blocks for classical and PQC → 2x verification effort
- No formal proof that constant-time claims are real
- Certification teams spend quarters reconstructing evidence

---

## Slide 3: The Solution

GSAF is a **single fabric** with pluggable engines:
- One scheduler, one isolation model, one proof story
- Engines plug in per customer via formally specified interface
- Verification evidence ships in the box

```
Host → AXI4-Lite → Scheduler → [ModExp] [ModInv] [PQC] [RSA-CRT] [ECC]
                                        ↑
                              Montgomery Cluster
                           (static lane reservation)
```

---

## Slide 4: Why GSAF Wins

| Feature | GSAF | Rambus/Synopsys | OpenTitan |
|---------|------|-----------------|-----------|
| PQC in same fabric | ✓ ML-KEM/ML-DSA | Separate IP | ✗ |
| Formal verification | SVA + golden model | Rarely shipped | ✗ |
| Constant-time proof | Machine-verified | Claimed only | Claimed |
| Evidence bundle | Signed, tiered | Custom engagement | ✗ |
| Multi-engine isolation | Static lanes | Varies | N/A |

**Key differentiator:** We don't sell a ModExp accelerator. We sell the **evidence bundle** that cuts certification timelines by quarters.

---

## Slide 5: What Ships Today

| Component | Status |
|-----------|--------|
| RTL (SystemVerilog SV-2017) | Production-intent |
| 5 crypto engines | All verified |
| AXI4-Lite interface | Standard bus integration |
| Golden models (Python) | Self-testing, exhaustive |
| cocotb testbenches | 4/4 pass per engine |
| Formal properties | SVA fabric + engine level |
| Evidence pack system | HMAC-signed, tiered |
| CLI tooling (GSAF Studio) | 15 commands |
| License server | Issue/validate/revoke/rotate |

---

## Slide 6: PQC Readiness

- **ML-KEM (Kyber):** FIPS 203 NTT, q=3329, zeta=17
- **ML-DSA (Dilithium):** FIPS 204 NTT, q=8380417, zeta=1753
- **Same butterfly engine** for both standards
- **Golden model verified** against schoolbook negacyclic convolution
- **Constant-time by construction** — NTT has fixed iteration count

---

## Slide 7: Security Countermeasures

| Threat | Countermeasure | Proof |
|--------|---------------|-------|
| DPA (power analysis) | Exponent blinding (64-bit) | Golden model invariant |
| Fault injection | Sparse FSM encoding + range checks | STATUS_FAULT never silent |
| Timing leakage | Fixed-latency operations | Formal SVA properties |
| Operand tampering | Static bank isolation | No cross-transaction leakage |

---

## Slide 8: Pricing

| Product | Price | Includes |
|---------|-------|----------|
| Chassis + Core Engines | $75K-$150K + 1.5% royalty | RTL + golden models + evidence pack |
| + PQC Engine | $150K-$300K + 2% royalty | ML-KEM/ML-DSA NTT |
| + Enterprise (Custom) | $300K-$500K + 2.5% royalty | Custom engines + obfuscated RTL |
| Certification Pack | $100K-$200K one-time | FIPS 140-3 evidence + CC docs |

---

## Slide 9: Roadmap

| Quarter | Milestone |
|---------|-----------|
| Q3 2026 | FPGA eval bitstream + PPA datasheet |
| Q4 2026 | TVLA side-channel capture |
| Q1 2027 | FIPS 140-3 CAVP engagement |
| Q2 2027 | Common Criteria documentation |
| Q3 2027 | Radix-4 CSA multiplier (4x throughput) |

---

## Slide 10: Next Steps

1. **NDA execution** — receive RTL source + evidence pack
2. **Technical evaluation** — 30-day access to GSAF Studio
3. **Design-in decision** — license agreement + royalty terms
4. **Integration support** — 40 hours included

**Contact:** _______________
