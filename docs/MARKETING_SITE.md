# GSAF Marketing Site Structure

## Site Map

```
gsaf.verily.com
├── /                          # Landing page
├── /product                   # Product overview
│   ├── /architecture          # Technical architecture
│   ├── /engines               # Engine catalog (ModExp, ModInv, PQC, RSA-CRT, ECC)
│   ├── /security              # Security countermeasures
│   └── /evidence              # Verification evidence approach
├── /resources
│   ├── /docs                  # Documentation hub
│   │   ├── /getting-started   # Quick start guide
│   │   ├── /soc-integration   # SoC integration guide
│   │   ├── /engine-sdk        # Custom engine development
│   │   ├── /fpga-guide        # FPGA evaluation
│   │   └── /cli-reference     # GSAF Studio CLI
│   ├── /ppa                   # PPA datasheet (estimated)
│   └── /whitepapers           # Technical whitepapers
├── /evaluate                  # Evaluation request form
│   └── /request               # NDA + access request
├── /pricing                   # Pricing overview
├── /about                     # Company info
└── /contact                   # Sales contact
```

## Page Content Outline

### Landing Page (`/`)
- Hero: "The Formally Verified Post-Quantum Transition Fabric"
- Sub: "One fabric. Five engines. Evidence in the box."
- 3 value props: PQC-ready, formally verified, evidence bundle
- CTA: "Request Evaluation"

### Product Overview (`/product`)
- Problem statement: PQC transition deadlines
- Solution: multi-engine fabric with formal verification
- Competitive comparison table
- Architecture diagram

### Engine Catalog (`/product/engines`)
- ModExp: specs, latency, DPA countermeasures
- ModInv: specs, Bernstein-Yang algorithm
- PQC NTT: FIPS 203/204 support, butterfly architecture
- RSA-CRT: Bellcore hardening, verify-after-sign
- ECC X25519: Montgomery ladder, constant-time

### Evidence Approach (`/product/evidence`)
- Why evidence matters for certification
- What's in the evidence pack
- Tier structure (free/paid/enterprise)
- How it cuts cert timelines

### PPA Datasheet (`/resources/ppa`)
- Per-engine resource estimates
- Latency formulas
- Comparison vs OpenTitan
- Configuration options (WIDTH, multipliers, banks)

### Evaluation Request (`/evaluate`)
- Form fields: name, company, email, target application
- Auto-triggers NDA process
- 30-day evaluation access

## Content Calendar

| Week | Deliverable |
|------|-------------|
| 1 | Landing page + product overview copy |
| 2 | Engine catalog pages + PPA datasheet |
| 3 | Documentation hub (docs already exist) |
| 4 | Evaluation request form + pricing page |
