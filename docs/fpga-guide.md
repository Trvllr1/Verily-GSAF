# GSAF FPGA Guide

## Overview

This guide covers FPGA synthesis, implementation, and deployment of the GSAF fabric for evaluation and testing purposes.

## Supported Targets

| Target | Part | Tool | Notes |
|--------|------|------|-------|
| Artix-7 | xc7a35tcpg236-1 | Vivado | Low-cost evaluation |
| Zynq-7000 | xc7z020clg400-1 | Vivado | SoC with ARM |
| Cyclone V | 5CEBA4F23C7 | Quartus | Intel FPGA |

## Quick Start

### 1. Synthesize for Artix-7

```bash
# Using Vivado TCL
vivado -mode batch -source fpga/synth-vivado.tcl -tclargs artix-7 xc7a35tcpg236-1

# Or using gsaf CLI
gsaf fpga build --target artix-7 --part xc7a35tcpg236-1
```

### 2. Run Benchmarks

```bash
gsaf fpga benchmark --engines modexp,modinv --clock 100MHz
```

### 3. Capture Power Traces for TVLA

```bash
gsaf fpga tvla --capture power_trace.vcd --traces 1000000
```

## Synthesis Scripts

### Vivado (`fpga/synth-vivado.tcl`)

```tcl
# Read RTL files
read_verilog -sv rtl/gf_pkg.sv
read_verilog -sv rtl/gf_fifo.sv
read_verilog -sv rtl/gf_mont_mult.sv
# ... all RTL files

# Set top module
set_top gf_secure_fabric_top

# Read constraints
read_xdc fpga/constraints/artix-7.xdc

# Synthesize
synth_design -top gf_secure_fabric_top -part $part

# Implement
opt_design
place_design
route_design

# Generate bitstream
write_bitstream -force output.bit
```

### Constraints (`fpga/constraints/artix-7.xdc`)

```xdc
# Clock
create_clock -period 10.000 -name clk_i -waveform {0.000 5.000} [get_ports clk_i]

# Reset
set_property PACKAGE_PIN C12 [get_ports rst_ni]
set_property IOSTANDARD LVCMOS33 [get_ports rst_ni]

# AXI4-Lite Interface
# AW channel
set_property PACKAGE_PIN A3 [get_ports {s_axil_awaddr[0]}]
# ... (full pin assignments)

# Timing constraints
set_max_delay -from [get_cells u_frontend/*] -to [get_cells u_scheduler/*] 8.000
```

## Resource Utilization

| Engine | LUTs | FFs | BRAM | DSP |
|--------|------|-----|------|-----|
| ModExp (WIDTH=256) | ~5K | ~3K | 4 | 8 |
| ModInv (WIDTH=256) | ~2K | ~1.5K | 0 | 0 |
| PQC NTT (WIDTH=23) | ~3K | ~2K | 2 | 4 |
| Full Fabric | ~15K | ~10K | 8 | 16 |

## Performance

| Metric | ModExp | ModInv | PQC NTT |
|--------|--------|--------|---------|
| Latency (cycles) | ~2K | ~1K | ~8K |
| Throughput (ops/sec) | 50K | 100K | 12.5K |
| Clock (MHz) | 100 | 100 | 100 |

## TVLA Testing

### Setup

1. Connect FPGA to power analysis equipment (ChipWhisperer, etc.)
2. Configure capture trigger on `valid_i` signal
3. Run fixed-vs-random test sets

### Test Sets

| Test | Fixed | Random | Traces |
|------|-------|--------|--------|
| ModExp (no blinding) | Fixed exponent | Random messages | 1M |
| ModExp (with blinding) | Fixed exponent + random k | Random messages | 1M |
| ModInv | Fixed input | Random inputs | 1M |
| Cross-engine | Fixed engine A | Random engine B | 1M |

### Analysis

```bash
# Analyze captured traces
python scripts/analyze_tvla.py power_trace.vcd --threshold 4.5
```

## Best Practices

1. **Clock domain crossing**: Use synchronizers for signals crossing clock domains
2. **Reset strategy**: Use synchronous reset for FPGA (async for ASIC)
3. **Timing closure**: Run timing analysis before bitstream generation
4. **Power analysis**: Use Vivado Power Estimator before synthesis
5. **Incremental synthesis**: Use checkpoint saved designs for faster iteration
