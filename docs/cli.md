# CLI Reference

## GSAF Studio CLI

The `gsaf` CLI provides commands for the full GSAF verification pipeline:

```bash
gsaf explore          # List RTL modules and interfaces
gsaf architect        # Validate architecture constraints
gsaf verify           # Run formal + simulation verification
gsaf assure           # Generate evidence pack
gsaf validate-engine  # Validate client engines against gf_engine_if
gsaf template         # Generate engine template
gsaf license          # Manage engine licensing
gsaf fpga             # FPGA synthesis and testing
gsaf version          # Show version
```

## Commands

### gsaf explore

Lists RTL modules, their interfaces, and formal verification status.

```bash
gsaf explore [--module MODULE] [--verbose]
```

| Option | Description |
|--------|-------------|
| `--module, -m` | Filter to a specific module name |
| `--verbose, -v` | Show detailed info (module count, etc.) |

### gsaf architect

Validates architecture constraints (WIDTH, bank count, multiplier count, etc.).

```bash
gsaf architect [--width WIDTH] [--banks BANKS] [--multipliers NUM] [--check-all]
```

| Option | Description |
|--------|-------------|
| `--width, -w` | Data path width (default: 64) |
| `--banks, -b` | Number of operand banks (default: 4) |
| `--multipliers, -m` | Number of multiplier lanes (default: 1) |
| `--check-all` | Check all constraints |

### gsaf verify

Runs formal verification and simulation, collects results.

```bash
gsaf verify [--formal] [--simulation] [--all] [--engine ENGINE_LIST]
```

| Option | Description |
|--------|-------------|
| `--formal` | Run formal verification only |
| `--simulation` | Run simulation only |
| `--all/--no-all` | Run all verification (default: yes) |
| `--engine, -e` | Comma-separated engines to verify (`modexp,modinv,pqc,rsa-crt,ecc`) |

Runs golden model self-tests, Verilator lint, formal verification (SymbiYosys), and cocotb dyno tests per engine.

### gsaf assure

Generates the evidence pack and validates completeness.

```bash
gsaf assure [--tier free|paid|enterprise] [--output DIR] [--verify]
```

| Option | Description |
|--------|-------------|
| `--tier, -t` | Evidence pack tier (default: `free`) |
| `--output, -o` | Output directory (default: `evidence-pack`) |
| `--verify` | Verify pack completeness after generation |

#### Evidence Pack Tiers

| Tier | Contents |
|------|----------|
| Free | `01_chassis/` only — RTL, golden models, lint, formal, simulation |
| Paid | `01_chassis/` + all `02_engine_*/` (modexp, modinv, pqc, rsa_crt, ecc) |
| Enterprise | Custom dynos, custom formal proofs, obfuscated RTL |

### gsaf validate-engine

Validates a client engine against `gf_engine_if.sv` and generates evidence.

```bash
gsaf validate-engine ENGINE_FILE [--golden-model MODEL] [--width WIDTH] [--output DIR] [--skip-formal] [--skip-sim]
```

| Option | Description |
|--------|-------------|
| `ENGINE_FILE` | Path to engine SystemVerilog file |
| `--golden-model, -g` | Path to golden model Python file |
| `--width, -w` | Data path width (default: 64) |
| `--output, -o` | Evidence output directory (default: `evidence-pack`) |
| `--skip-formal` | Skip formal verification |
| `--skip-sim` | Skip simulation tests |

Steps performed:
1. Verilator lint
2. Yosys synthesis check
3. Formal verification (SymbiYosys)
4. Simulation (cocotb dyno test)
5. Evidence pack generation

### gsaf template

Generate a starter engine template.

```bash
gsaf template ENGINE_NAME [--width WIDTH] [--output DIR]
```

| Option | Description |
|--------|-------------|
| `ENGINE_NAME` | Engine name (e.g., `my_ntt_engine`) |
| `--width, -w` | Data path width (default: 64) |
| `--output, -o` | Output directory (default: `rtl`) |

### gsaf license

Manage engine licensing — generate, validate, sign, and verify evidence packs.

```bash
gsaf license generate ENGINE [--key KEY] [--output DIR]
gsaf license validate ENGINE_FILE --key KEY
gsaf license sign EVIDENCE_DIR --key KEY
gsaf license verify EVIDENCE_DIR --key KEY
```

| Subcommand | Description |
|------------|-------------|
| `generate` | Generate a license key for an engine |
| `validate` | Validate that an engine has a LICENSE_KEY parameter |
| `sign` | Sign an evidence pack with HMAC-SHA256 |
| `verify` | Verify evidence pack signature |

### gsaf fpga

FPGA synthesis, benchmarking, and TVLA side-channel testing.

```bash
gsaf fpga build [--target TARGET] [--part PART] [--clock FREQ]
gsaf fpga benchmark [--engines LIST] [--clock FREQ] [--traces N]
gsaf fpga tvla [--capture FILE] [--traces N] [--threshold T]
gsaf fpga analyze TRACE_FILE [--threshold T]
```

| Subcommand | Description |
|------------|-------------|
| `build` | Synthesize GSAF for FPGA (requires Vivado) |
| `benchmark` | Run FPGA benchmarks for specified engines |
| `tvla` | Configure TVLA side-channel testing |
| `analyze` | Analyze captured TVLA traces |

### gsaf version

Show GSAF Studio version.

```bash
gsaf version
```
