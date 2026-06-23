#!/bin/bash
# GSAF Simulation Environment Setup — clean WSL/Ubuntu
# Uses cocotb 1.9.2 (stable Makefile.sim support)
set -e

echo "=== GSAF Simulation Environment Setup ==="

# Check for Verilator
if ! command -v verilator &>/dev/null; then
    echo "Verilator not found. Installing..."
    sudo apt update && sudo apt install -y verilator
fi
echo "Verilator: $(verilator --version)"

echo "Python: $(python3 --version)"

# Install cocotb 1.9.2 globally (--user)
echo "Installing cocotb 1.9.2..."
pip3 install --user --break-system-packages "cocotb==1.9.2" cocotbext-axi

# Add ~/.local/bin to PATH for this session and future shells
export PATH="$HOME/.local/bin:$PATH"
grep -q '\.local/bin' ~/.bashrc 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc

# Verify
echo ""
echo "cocotb version: $(python3 -c 'import cocotb; print(cocotb.__version__)')"
echo "Makefile.sim:   $(cocotb-config --makefiles)/Makefile.sim"

# Remove stale files
rm -f ~/Verily-GSAF/tb/run_test.py

echo ""
echo "=== Setup complete ==="
echo "To use:"
echo "  cd ~/Verily-GSAF/tb"
echo "  rm -rf sim_build"
echo "  make test SIM=verilator"
