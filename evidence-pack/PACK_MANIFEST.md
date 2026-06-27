# GSAF Evidence Pack — Manifest

**Version:** 0.2.0
**Date:** 2026-06-25
**Build Hash:** TBD (populated by `make evidence`)

## Contents

| Folder | Description | Status |
|--------|-------------|--------|
| `01_chassis/` | Chassis RTL verification evidence | Ready |
| `02_engine_modexp/` | ModExp engine verification evidence | Ready |
| `02_engine_modinv/` | ModInv engine verification evidence | Ready |
| `02_engine_pqc/` | PQC NTT engine verification evidence | Ready |
| `02_engine_rsa_crt/` | RSA-CRT engine verification evidence | Ready |
| `02_engine_ecc/` | ECC X25519 engine verification evidence | Ready |

## Evidence Pack Tiers

| Tier | Contents | Use Case |
|------|----------|----------|
| Free | `01_chassis/` only | Open-source users |
| Paid | `01_chassis/` + all `02_engine_*/` | Commercial licensees |
| Enterprise | Custom dynos + formal proofs | Custom engine development |

## Key Principle

When a client swaps engines, they swap the `02_engine_*` folder. The `01_chassis/` evidence stays valid because the chassis was verified against the formal interface spec, not against any specific engine.

## Generation

```bash
# Generate complete evidence pack
make evidence

# Or use the CLI
gsaf assure --tier paid
```
