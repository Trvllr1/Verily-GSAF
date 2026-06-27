# GSAF Certification Gap Analysis

## Overview

This document maps GSAF's current state against FIPS 140-3 and Common Criteria (CC) requirements, identifies gaps, and provides a roadmap for certification readiness.

---

## FIPS 140-3 (Cryptographic Module)

### Level Requirements

| Level | Description | GSAF Target |
|-------|-------------|-------------|
| Level 1 | Basic security | Achievable now |
| Level 2 | tamper-evident + role-based auth | Near-term |
| Level 3 | physical tamper resistance + identity-based auth | Medium-term |
| Level 4 | complete envelope of physical security | Not targeted |

### Algorithm Certifications (CAVP)

| Algorithm | FIPS Standard | GSAF Implementation | Status |
|-----------|--------------|---------------------|--------|
| RSA (ModExp) | FIPS 186-5 | gf_modexp_engine | ✅ RTL ready |
| RSA (ModInv) | SP 800-56B Rev 2 | gf_modinv_engine | ✅ RTL ready |
| ECC (X25519) | SP 800-186 | gf_ecc_engine | ✅ RTL ready |
| AES | FIPS 197 | Not implemented | ❌ Gap |
| SHA-2/SHA-3 | FIPS 180-4 / FIPS 202 | Not implemented | ❌ Gap |
| DRBG | SP 800-90A | Not implemented | ❌ Gap |
| ML-KEM | FIPS 203 | gf_pqc_engine (NTT) | ✅ RTL ready |
| ML-DSA | FIPS 204 | gf_pqc_engine (NTT) | ✅ RTL ready |
| HMAC | FIPS 198-1 | Not implemented | ❌ Gap |
| CVL (DRBG/KAS) | SP 800-56A/B | Not implemented | ❌ Gap |

### Module Security Requirements

| Requirement | GSAF Status | Gap |
|-------------|-------------|-----|
| Cryptographic module specification | ✅ Architecture doc | Complete |
| Ports and interfaces | ✅ AXI4-Lite spec | Complete |
| Roles, services, authentication | ❌ No auth model | Need role-based access |
| Finite state model | ✅ FSM documented | Complete |
| Physical security | N/A (IP core) | Customer responsibility |
| Operational environment | N/A (RTL) | Customer responsibility |
| Key management | ⚠️ Basic license keys | Need proper KMS |
| Self-tests | ✅ Golden model self-tests | Complete |
| Design assurance | ⚠️ Partial | Need full design assurance |
| Mitigation of attacks | ✅ DPA + fault countermeasures | Complete |
| Policy | ❌ No security policy | Need CC-style policy |

### CAVP Testing Flow

```
1. Implement algorithm per FIPS spec
2. Generate test vectors
3. Submit to NVLAP-accredited lab (e.g., Acumen, Gossamer)
4. Lab runs CAVP test suite
5. Lab issues algorithm certificate
6. Certificate有效期: 3 years
```

**Cost estimate:** $15K-$30K per algorithm, $50K-$100K total for ModExp + ModInv + ECC

---

## Common Criteria (CC)

### Target: EAL2+ (Evaluation Assurance Level 2+)

| EAL | Description | GSAF Target |
|-----|-------------|-------------|
| EAL1 | Functionally tested | ✅ Achievable now |
| EAL2 | Structurally tested | ✅ Achievable with documentation |
| EAL3 | Methodically tested and checked | Medium-term |
| EAL4 | Methodically designed, reviewed, and tested | Not targeted |

### CC Components

| Component | Requirement | GSAF Status | Gap |
|-----------|-------------|-------------|-----|
| ADV_ARC | Architecture description | ✅ ARCHITECTURE.md | Complete |
| ADV_FSP | Functional specification | ✅ Interface spec | Complete |
| ADV_IMP | Implementation representation | ✅ RTL source | Complete |
| ADV_INT | Internals documentation | ⚠️ Partial | Need more |
| ADV_LCD | Development environment config | ❌ Not started | Gap |
| ADV_TDS | Design representation | ✅ Microarchitecture doc | Complete |
| AGD_OPE | Operational user guidance | ❌ Not started | Need user manual |
| AGD_PRE | Preparative procedures | ❌ Not started | Need install guide |
| ALC_CMC | Configuration management | ⚠️ Git + CI | Need formal CM plan |
| ALC_CMS | Configuration management scope | ⚠️ Partial | Gap |
| ALC_DEL | Delivery procedures | ❌ Not started | Need delivery process |
| ALC_DVS | Development security | ❌ Not started | Gap |
| ALC_FLR | Flaw remediation | ❌ Not started | Gap |
| ALC_TAT | Tool assessment | ⚠️ Yosys + Verilator | Need formal assessment |
| ATE_CPT | Capabilities testing | ✅ cocotb tests | Complete |
| ATE_DPT | Depth-of-testing | ⚠️ Partial | Need coverage metrics |
| ATE_FUN | Functional testing | ✅ Golden model + cocotb | Complete |
| ATE_IND | Independent testing | ❌ Not started | Need 3rd party |
| AVA_CCA | Vulnerability assessment | ⚠️ Partial | Need formal analysis |
| AVA_MSU | Misuse scenario analysis | ❌ Not started | Gap |
| AVA_VAN | Vulnerability analysis | ❌ Not started | Gap |

### CC Documentation Package

| Document | Purpose | Status |
|----------|---------|--------|
| Security Target (ST) | Define security claims | ❌ Not started |
| Security Target Rationale | Justify claims vs threats | ❌ Not started |
| Test Plan | Describe testing approach | ✅ VERIFICATION_PLAN.md |
| Test Results | Evidence of testing | ⚠️ Partial (cocotb results) |
| Design Documentation | Internal design description | ✅ ARCHITECTURE.md |
| Delivery Procedures | How IP is delivered | ❌ Not started |
| Guidance Documents | User/operator guidance | ❌ Not started |
| Vulnerability Analysis | Known weaknesses | ❌ Not started |

**Cost estimate:** $100K-$200K for EAL2+ evaluation (lab fees + documentation)

---

## Gap Summary

### Critical Gaps (Must Fix Before Certification)

| Gap | Impact | Effort | Priority |
|-----|--------|--------|----------|
| Security Target document | Required for CC | 2-4 weeks | Critical |
| Test coverage metrics | Required for ATE_DPT | 1-2 weeks | Critical |
| Delivery procedures | Required for ALC_DEL | 1 week | Critical |
| Vulnerability analysis | Required for AVA_VAN | 2-3 weeks | Critical |
| CAVP test vectors | Required for FIPS | 1-2 weeks | Critical |

### Important Gaps (Should Fix)

| Gap | Impact | Effort | Priority |
|-----|--------|--------|----------|
| Role-based access model | FIPS Level 2+ | 1-2 weeks | High |
| Key management spec | FIPS key lifecycle | 1-2 weeks | High |
| Configuration management plan | CC ALC_CMC | 1 week | High |
| User guidance document | CC AGD_OPE | 1-2 weeks | High |
| Independent test results | CC ATE_IND | 2-4 weeks | High |

### Nice-to-Have Gaps

| Gap | Impact | Effort | Priority |
|-----|--------|--------|----------|
| AES/SHA/HMAC engines | FIPS module completeness | 4-6 weeks | Medium |
| Formal CM plan | CC ALC_CMS | 1 week | Medium |
| Misuse scenario analysis | CC AVA_MSU | 1-2 weeks | Medium |

---

## Certification Timeline

### Phase 1: Pre-Certification (Now → Q4 2026)
- [ ] Write Security Target document
- [ ] Complete test coverage metrics
- [ ] Write delivery procedures
- [ ] Conduct vulnerability analysis
- [ ] Generate CAVP test vectors for ModExp/ModInv

### Phase 2: CAVP Testing (Q1 2027)
- [ ] Engage NVLAP-accredited lab
- [ ] Submit ModExp for CAVP testing
- [ ] Submit ModInv for CAVP testing
- [ ] Submit ECC for CAVP testing
- [ ] Receive algorithm certificates

### Phase 3: CC Evaluation (Q2-Q3 2027)
- [ ] Engage CC evaluation lab
- [ ] Submit for EAL2+ evaluation
- [ ] Address any findings
- [ ] Receive CC certificate

### Phase 4: Certification Pack (Q4 2027)
- [ ] Bundle all certificates + evidence
- [ ] Create certification pack product
- [ ] Price at $100K-$200K per customer

---

## Cost Summary

| Item | Estimated Cost | Timing |
|------|---------------|--------|
| CAVP testing (3 algorithms) | $50K-$100K | Q1 2027 |
| CC EAL2+ evaluation | $100K-$200K | Q2-Q3 2027 |
| Documentation (ST, guides) | $30K-$50K (internal) | Q3-Q4 2026 |
| TVLA side-channel testing | $20K-$40K | Q4 2026 |
| **Total** | **$200K-$390K** | **12-18 months** |

### Revenue Potential

| Scenario | Customers | Revenue/Customer | Total |
|----------|-----------|-----------------|-------|
| Without cert | 5 | $150K | $750K |
| With FIPS CAVP | 10 | $200K | $2M |
| With CC EAL2+ | 15 | $300K | $4.5M |
| Full cert pack | 10 | $400K | $4M |

**Certification ROI:** $200K-$390K investment → $2M-$4.5M additional revenue over 3 years.
