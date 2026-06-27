# GSAF Competitive Matrix

## Executive Summary

GSAF differentiates on **verification evidence** and **PQC integration**, not raw throughput. Competitors own the classical crypto IP market through scale and relationships. GSAF wins where certification timelines and post-quantum readiness matter.

---

## Head-to-Head Comparison

| Feature | GSAF | Rambus CryptoManager | Synopsys DWC | OpenTitan BigNum | CEVA CryptoProcessor |
|---------|------|---------------------|--------------|------------------|---------------------|
| **Type** | RTL IP core | RTL IP + firmware | RTL IP core | Open-source RTL | RTL IP + software |
| **License** | Per-design + royalty | Per-design + royalty | Per-design + royalty | Apache 2.0 (free) | Per-design + royalty |
| **Price range** | $75K-$500K | $200K-$1M+ | $150K-$600K | $0 (integration cost ~$300K) | $200K-$400K |
| **PQC support** | ✅ ML-KEM + ML-DSA in-fabric | ⚠️ Roadmap | ⚠️ Roadmap | ✗ Not included | ✗ Not included |
| **Formal verification** | ✅ SVA properties + golden model | Rarely shipped | Partial | ✗ | ✗ |
| **Constant-time proof** | ✅ Machine-verified | Claimed | Claimed | Claimed | Claimed |
| **Evidence bundle** | ✅ Signed, tiered, cert-ready | Custom engagement | Custom engagement | ✗ None | ✗ None |
| **Bus interface** | AXI4-Lite | AXI4/AHB | AXI4/AHB | TileLink | AXI4/AHB |
| **Multi-engine** | ✅ Pluggable chassis | Fixed | Fixed | Single engine | Fixed |
| **FIPS 140-3** | CAVP in progress | ✅ Certified | ✗ Not certified | ✗ Not certified | ✗ Not certified |
| **Common Criteria** | EAL2+ planned | ✅ EAL4+ | ✗ | ✗ | ✗ |
| **TVLA side-channel** | Planned (Q4 2026) | ✅ Published | ✗ Not published | ✗ | ✗ |
| **FPGA eval** | Artix-7 (planned) | Multiple boards | Multiple boards | Google FPGA | ✗ |
| **Driver/FW** | C driver example | Full SDK | Full SDK | RISC-V driver | Full SDK |
| **Support** | Direct engineering | Enterprise | Enterprise | Community | Enterprise |

---

## Detailed Feature Comparison

### Classical Crypto

| Feature | GSAF | Rambus | Synopsys | OpenTitan |
|---------|------|--------|----------|-----------|
| ModExp (RSA) | ✅ Fixed-window w=4 | ✅ Multi-window | ✅ Multi-window | ✅ BigNum |
| ModInv | ✅ Bernstein-Yang | ✅ Extended Euclidean | ✅ | ✗ |
| RSA-CRT | ✅ Bellcore hardened | ✅ | ✅ | ✗ |
| ECC (X25519) | ✅ Montgomery ladder | ✅ Multiple curves | ✅ Multiple curves | ✗ |
| AES | ✗ Not included | ✅ | ✅ | ✅ |
| SHA-2/3 | ✗ Not included | ✅ | ✅ | ✅ |
| DRBG | ✗ Not included | ✅ | ✅ | ✅ |

**Assessment:** GSAF covers the core public-key operations (ModExp, ModInv, RSA-CRT, ECC) but lacks symmetric crypto (AES, SHA, DRBG). Customers need these from another source or GSAF adds them.

### Post-Quantum Crypto

| Feature | GSAF | Rambus | Synopsys | OpenTitan |
|---------|------|--------|----------|-----------|
| ML-KEM (Kyber) | ✅ NTT engine | ⚠️ Roadmap 2027 | ⚠️ Roadmap | ✗ |
| ML-DSA (Dilithium) | ✅ NTT engine (same hw) | ⚠️ Roadmap 2027 | ⚠️ Roadmap | ✗ |
| FIPS 203/204 compliance | ✅ Golden model verified | TBD | TBD | N/A |
| Hybrid classical+PQC | ✅ Same fabric | Separate IP | Separate IP | N/A |

**Assessment:** GSAF has a 1-2 year lead on PQC integration. Competitors are still on roadmaps. This is the primary sales wedge.

### Security Properties

| Property | GSAF | Rambus | Synopsys | OpenTitan |
|----------|------|--------|----------|-----------|
| Constant-time by construction | ✅ Proven | Claimed | Claimed | Claimed |
| DPA countermeasures | ✅ Exponent blinding | ✅ | ✅ | ✅ |
| Fault injection detection | ✅ Sparse FSM + range checks | ✅ | ✅ | ✗ |
| Formal SVA properties | ✅ 5 fabric + 5 engine | ✗ | ✗ | ✗ |
| Golden model equivalence | ✅ Self-testing | ✗ | ✗ | ✗ |
| Secure wipe on retire | ✅ Static bank wipe | ✅ | ✅ | ✗ |

**Assessment:** GSAF's formal verification and golden model are unique in the market. No competitor ships proof artifacts with their IP.

### Integration

| Feature | GSAF | Rambus | Synopsys | OpenTitan |
|---------|------|--------|----------|-----------|
| Bus interface | AXI4-Lite | AXI4/AHB | AXI4/AHB | TileLink |
| Configurable width | ✅ 8-4096 bit | ✅ | ✅ | Fixed |
| Multiplier lanes | 1-8 (configurable) | Fixed | Fixed | N/A |
| Operand banks | 1-8 (configurable) | Fixed | Fixed | N/A |
| Transaction depth | Configurable | Fixed | Fixed | N/A |
| Clock gating support | ✅ idle_o signal | ✅ | ✅ | ✗ |
| Interrupt support | ✅ Level-triggered | ✅ | ✅ | ✅ |

**Assessment:** GSAF's configurability (WIDTH, lanes, banks) is a differentiator for customers with specific area/timing constraints.

---

## Competitive Positioning Matrix

| Dimension | GSAF Position | Competitor Position | Winner |
|-----------|--------------|--------------------|--------| 
| Price | Mid-range ($75K-$500K) | High ($150K-$1M+) | GSAF |
| PQC readiness | Production-ready | Roadmap | **GSAF** |
| Formal verification | Shipped with IP | Not shipped | **GSAF** |
| Evidence bundle | Signed, tiered, cert-ready | Custom engagement | **GSAF** |
| Certification (FIPS/CC) | In progress | Rambus: certified | Rambus |
| Symmetric crypto | Not included | Full suite | Competitors |
| Driver/FW ecosystem | Minimal | Mature | Competitors |
| Support/SLA | Direct engineering | Enterprise | Competitors |
| Market trust | Startup | Established | Competitors |

---

## Win/Loss Scenarios

### GSAF Wins When:
1. Customer needs **PQC + classical in one fabric** (hybrid transition)
2. Customer's **cert team needs evidence** to cut timeline
3. Customer is **pre-silicon** and can tolerate startup risk
4. Customer wants **formal proof artifacts** (not just claims)
5. Customer has **tight area budget** (GSAF's configurable width helps)

### GSAF Loses When:
1. Customer needs **full crypto suite** (AES, SHA, DRBG, HMAC)
2. Customer requires **FIPS/CC certificate today** (not in progress)
3. Customer is **risk-averse** and prefers established vendors
4. Customer needs **mature SDK/driver ecosystem**
5. Customer's timeline is **< 6 months to silicon** (need proven IP)

---

## GSAF Differentiation Statement

> "GSAF is the only crypto IP that ships formal proofs, golden-model equivalence, and signed evidence in the box. While competitors claim constant-time, we prove it. While competitors roadmap PQC, we ship it. The evidence bundle saves your cert team quarters — that's the real value proposition."

---

## Pricing Positioning

| Tier | GSAF | Rambus | Synopsys | OpenTitan |
|------|------|--------|----------|-----------|
| Entry | $75K | $200K+ | $150K+ | $0 |
| Mid | $150K-$300K | $400K-$600K | $300K-$500K | $0 |
| Enterprise | $300K-$500K | $800K-$1M+ | $500K-$800K | $0 |
| Royalty | 1.5-2.5% | 2-3% | 1-2% | 0% |
| Cert pack | $100K-$200K | Custom | Custom | N/A |

**Key pricing message:** GSAF offers similar capabilities to Rambus/Synopsys at 40-60% lower cost, with PQC and evidence included (not add-on).
