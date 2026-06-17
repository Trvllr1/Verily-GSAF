#!/bin/bash
# GSAF Simulation Environment Setup
#
# cocotb + Verilator simulation requires Linux or WSL2.
# cocotb does not ship cocotbvpi_verilator.dll for Windows.
#
# Prerequisites (Ubuntu/Debian):
#   sudo apt install verilator python3-pip python3-venv
#
# Setup:
#   bash scripts/setup_sim.sh

set -e

echo "=== GSAF Simulation Environment Setup ==="

# Check for Verilator
if ! command -v verilator &>/dev/null; then
    echo "Verilator not found. Installing..."
    if command -v apt &>/dev/null; then
        sudo apt update && sudo apt install -y verilator
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y verilator
    elif command -v pacman &>/dev/null; then
        sudo pacman -S verilator
    else
        echo "ERROR: Cannot auto-install verilator. Please install manually."
        exit 1
    fi
fi

echo "Verilator: $(verilator --version)"

# Create virtual environment
VENV_DIR=".venv"
if [ ! -d "$VENV_DIR" ]; then
    echo "Creating virtual environment..."
    python3 -m venv "$VENV_DIR"
fi

# Activate and install dependencies
source "$VENV_DIR/bin/activate"
echo "Python: $(python --version)"

pip install --upgrade pip
pip install cocotb cocotbext-axi typer rich

echo ""
echo "Setup complete. Activate the venv:"
echo "  source .venv/bin/activate"
echo ""
echo "Run tests:"
echo "  cd tb/dynos && make test-modexp"
echo "  cd tb/dynos && make test-all"
