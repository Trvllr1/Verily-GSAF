# CLI Reference

## GSAF Studio CLI

The `gsaf` CLI provides four commands for working with the GSAF fabric:

```bash
gsaf explore     # Explore RTL modules and interfaces
gsaf architect   # Validate architecture constraints
gsaf verify      # Run formal + simulation verification
gsaf assure      # Generate evidence pack
```

## Commands

### gsaf explore

Lists RTL modules, their interfaces, and formal verification status.

```bash
gsaf explore [--module MODULE] [--verbose]
```

### gsaf architect

Validates architecture constraints (WIDTH, bank count, multiplier count, etc.).

```bash
gsaf architect [--width WIDTH] [--banks BANKS] [--check-all]
```

### gsaf verify

Runs formal verification and simulation, collects results.

```bash
gsaf verify [--formal] [--simulation] [--all]
```

### gsaf assure

Generates the evidence pack and validates completeness.

```bash
gsaf assure [--tier free|paid|enterprise] [--output DIR]
```

## Evidence Pack Tiers

| Tier | Contents |
|------|----------|
| Free | `01_chassis/` only |
| Paid | `01_chassis/` + all `02_engine_*/` |
| Enterprise | Custom dynos, custom formal proofs |
