# Evidence Packs

## Overview

Evidence packs are structured directories containing verification artifacts that prove the security properties of the GSAF fabric. They are the primary deliverable for certification and customer handoff.

## Directory Structure

```
evidence-pack/
├── PACK_MANIFEST.md              # Version, date, build hash
├── 01_chassis/                   # Chassis evidence
│   ├── rtl/                      # Frozen RTL snapshot
│   ├── formal/                   # Formal proof results
│   ├── simulation/               # Simulation results
│   ├── golden_model/             # Golden model output
│   └── README.md                 # Evidence narrative
├── 02_engine_modexp/             # ModExp engine evidence
│   ├── dyno/                     # Engine test harness
│   ├── formal/                   # Engine formal proofs
│   └── README.md
├── 02_engine_modinv/             # ModInv engine evidence
│   ├── dyno/
│   ├── formal/
│   └── README.md
├── 02_engine_pqc/                # PQC NTT engine evidence
│   ├── dyno/
│   ├── formal/
│   └── README.md
├── 02_engine_rsa_crt/            # RSA-CRT engine evidence
│   ├── dyno/
│   ├── formal/
│   └── README.md
└── 02_engine_ecc/                # ECC X25519 engine evidence
    ├── dyno/
    ├── formal/
    └── README.md
```

## Key Principle

When a client swaps engines, they swap the `02_engine_*` folder. The `01_chassis/` evidence stays valid because the chassis was verified against the formal interface spec, not against any specific engine.

## Evidence Pack Tiers

| Tier | Contents | Use Case |
|------|----------|----------|
| Free | `01_chassis/` only | Open-source users |
| Paid | `01_chassis/` + all `02_engine_*/` | Commercial licensees |
| Enterprise | Custom dynos + formal proofs | Custom engine development |

## Engine Evidence Summary

| Engine | Golden Model | cocotb Tests | Formal Props | Status |
|--------|-------------|--------------|--------------|--------|
| ModExp | Exhaustive moduli, randomized | 4/4 PASS | P1-P5 fabric + engine SVA | Production-ready |
| ModInv | Exhaustive moduli, randomized | 4/4 PASS | P1-P5 fabric + engine SVA | Production-ready |
| PQC NTT | FIPS 203/204 verified, schoolbook cross-check | 4/4 PASS | Engine SVA | Production-ready |
| RSA-CRT | Bellcore detection, large primes | 4/4 PASS | Engine SVA | Production-ready |
| ECC X25519 | RFC 7748 vectors | 4/4 PASS | Engine SVA | Production-ready |

## Generating Evidence

```bash
# Generate complete evidence pack
make evidence

# Or use the CLI
gsaf assure --tier paid
```
