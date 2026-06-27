# GSAF Technical Sales Deck

## Slide 1: Title

**GSAF — The Fabric**
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
Host → AXI4-Lite → CryptoKast → [SAFMex] [SAFInv] [PiQ/SaV] [Didym] [Oxym]
                                         ↑
                               Montgomery Cluster
                            (static lane reservation)
```

---

## Slide 4: Why GSAF Wins

| Feature | GSAF | Rambus/Synopsys | OpenTitan |
|---------|------|-----------------|-----------|
| PQC in same fabric | ✓ PiQ + SaV | Separate IP | ✗ |
| Formal verification | SVA + golden model | Rarely shipped | ✗ |
| Constant-time proof | Machine-verified | Claimed only | Claimed |
| Evidence bundle | Signed, tiered | Custom engagement | ✗ |
| Multi-engine isolation | Static lanes | Varies | N/A |

**Key differentiator:** We don't sell a SAFMex accelerator. We sell the **evidence bundle** that cuts certification timelines by quarters.

---

## Slide 5: What Ships Today

| Component | Brand | Status |
|-----------|-------|--------|
| Chassis | CryptoKast | Production-intent |
| Modular exponentiation | SAFMex | Verified |
| Modular inverse | SAFInv | Verified |
| Post-quantum KEM | PiQ (Piquant) | Verified |
| Post-quantum DSA | SaV (Savant) | Verified |
| RSA-CRT | Didym | Verified |
| ECC X25519 | Oxym | Verified |
| Combined KEM+DSA | Compo | Verified |
| License server | — | Issue/validate/revoke/rotate |
| CLI tooling | GSAF Studio | 15 commands |

---

## Slide 6: PQC Readiness

- **PiQ (Piquant):** ML-KEM NTT — FIPS 203, q=3329, zeta=17
- **SaV (Savant):** ML-DSA NTT — FIPS 204, q=8380417, zeta=1753
- **Compo:** Combined KEM+DSA engine for customers needing both
- **Same butterfly architecture** across PiQ, SaV, Compo
- **Golden model verified** against schoolbook negacyclic convolution
- **Constant-time by construction** — NTT has fixed iteration count

---

## Slide 7: Security Countermeasures

| Threat | Countermeasure | Engine |
|--------|---------------|--------|
| DPA (power analysis) | Exponent blinding (64-bit) | SAFMex, Didym |
| Bellcore fault attack | Verify-after-sign | Didym |
| Timing leakage | Fixed-latency operations | All engines |
| Operand tampering | Static bank isolation | CryptoKast |
| Fault injection | Sparse FSM + range checks | SAFMex, SAFInv |

---

## Slide 8: Pricing — À La Carte

| Product | Price | Includes |
|---------|-------|----------|
| CryptoKast (base) | $75K-$150K + 1.5% royalty | Chassis + interface + evidence |
| + SAFMex | Individual or bundle | Modular exponentiation |
| + SAFInv | Individual or bundle | Modular inverse |
| + PiQ | Individual or bundle | ML-KEM NTT |
| + SaV | Individual or bundle | ML-DSA NTT |
| + Compo | Individual or bundle | KEM+DSA combined |
| + Didym | Individual or bundle | RSA-CRT |
| + Oxym | Individual or bundle | ECC X25519 |
| Classical bundle | $150K-$300K + 2% royalty | CryptoKast + SAFMex + SAFInv |
| PQC bundle | $150K-$300K + 2% royalty | CryptoKast + PiQ + SaV |
| Full fabric | $300K-$500K + 2.5% royalty | CryptoKast + all engines |
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
3. **Design-in decision** — pick your engines, license agreement
4. **Integration support** — 40 hours included

**Contact:** _______________
