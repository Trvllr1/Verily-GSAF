# Getting Started

## Prerequisites

- Python 3.10+
- MSYS2 with MinGW64 (Windows) or equivalent (Linux/macOS)
- Verilator 5.x
- Icarus Verilog 13.x
- Yosys 0.56+
- SymbiYosys (sby)
- cocotb 2.0+

## Installation

### Windows (MSYS2)

```bash
# Install MSYS2 from https://www.msys2.org/
# Then in MSYS2 MinGW64 shell:

# Install EDA tools
pacman -S mingw-w64-x86_64-verilator mingw-w64-x86_64-iverilog mingw-w64-x86_64-yosys

# Install SymbiYosys from source
cd /tmp
git clone https://github.com/YosysHQ/sby.git
cd sby
make install PREFIX=/mingw64

# Install Python packages
pip install cocotb cocotbext-axi typer rich
```

### Linux/macOS

```bash
# Ubuntu/Debian
sudo apt-get install verilator iverilog yosys

# Install SymbiYosys
git clone https://github.com/YosysHQ/sby.git
cd sby
sudo make install

# Python packages
pip install cocotb cocotbext-axi typer rich
```

## Verification

```bash
# Check all tools are installed
make check-tools

# Run golden model self-tests
make golden-test

# Run simulation
make sim

# Run formal verification
make formal
```

## Project Structure

```
Verily-GSAF/
├── rtl/              # Synthesizable SystemVerilog
├── model/            # Python golden models
├── tb/               # Testbenches (cocotb + SV)
├── fv/               # Formal properties
├── formal/           # SymbiYosys proof scripts
├── sim/              # Simulation filelists
├── docs/             # Documentation (MkDocs)
├── evidence-pack/    # Generated evidence bundle
└── Makefile          # Build automation
```
