#!/usr/bin/env python3
"""
GSAF Engine Obfuscation Tool

Obfuscates engine RTL for IP protection. Uses Yosys for synthesis and
signal renaming, then applies additional obfuscation transforms.

Usage:
    python scripts/obfuscate_engine.py rtl/my_engine.sv --output rtl/my_engine_obf.sv
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path
import hashlib
import random


def generate_license_hash(engine_name: str, secret_key: str) -> str:
    """Generate a deterministic license hash for the engine."""
    data = f"{engine_name}:{secret_key}"
    return hashlib.sha256(data.encode()).hexdigest()[:64]


def obfuscate_signals(content: str, seed: int = None) -> str:
    """Rename internal signals to obfuscated names."""
    if seed is None:
        seed = hash(content) & 0xFFFFFFFF
    rng = random.Random(seed)
    
    # Find internal signals (logic, reg declarations)
    signal_pattern = re.compile(r'\b(logic|reg)\s+(?:\[[\d:]+\]\s+)?(\w+)\b')
    
    signals = set()
    for match in signal_pattern.finditer(content):
        signals.add(match.group(2))
    
    # Generate obfuscated names
    obf_map = {}
    for sig in signals:
        # Skip standard signals
        if sig in ['clk_i', 'rst_ni', 'valid_i', 'ready_o', 'valid_o', 'ready_i',
                    'result_o', 'status_o', 'idle_o', 'state_q', 'state_d']:
            continue
        obf_name = f"_obf_{rng.randint(0, 0xFFFFFF):06x}"
        obf_map[sig] = obf_name
    
    # Apply renaming
    for original, obfuscated in obf_map.items():
        content = re.sub(r'\b' + re.escape(original) + r'\b', obfuscated, content)
    
    return content


def add_license_check(content: str, license_hash: str) -> str:
    """Add license key parameter and validation check."""
    license_param = f"""
  // License key (provided by Verily)
  parameter [255:0] LICENSE_KEY = 256'h0,
  localparam LICENSE_VALID = (LICENSE_KEY == 256'h{license_hash});
"""
    
    # Insert after parameter declarations
    content = content.replace(
        "parameter int unsigned WIDTH = gf_pkg::GF_WIDTH_DEFAULT",
        f"parameter int unsigned WIDTH = gf_pkg::GF_WIDTH_DEFAULT,\n{license_param}"
    )
    
    # Add license check to state machine
    license_check = """
  // License validation - engine only processes if licensed
  wire engine_enabled = LICENSE_VALID;
"""
    content = content.replace(
        "// ─── State machine",
        f"// ─── State machine{license_check}"
    )
    
    return content


def obfuscate_with_yosys(engine_path: str, output_path: str):
    """Use Yosys for synthesis-based obfuscation."""
    cmd = f"""yosys -p "
read_verilog -Irtl rtl/gf_pkg.sv {engine_path};
synth -flatten;
write_verilog {output_path};
" 2>&1"""
    
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Yosys warning: {result.stderr[:200]}")
    return result.returncode == 0


def main():
    parser = argparse.ArgumentParser(description="GSAF Engine Obfuscation Tool")
    parser.add_argument("engine", help="Path to engine SystemVerilog file")
    parser.add_argument("--output", "-o", help="Output path for obfuscated engine")
    parser.add_argument("--secret-key", "-k", default="verily-gsaf-2026",
                       help="Secret key for license hash generation")
    parser.add_argument("--seed", "-s", type=int, help="Random seed for obfuscation")
    parser.add_argument("--no-yosys", action="store_true",
                       help="Skip Yosys synthesis obfuscation")
    args = parser.parse_args()
    
    engine_path = Path(args.engine)
    if not engine_path.exists():
        print(f"Error: Engine file not found: {args.engine}")
        sys.exit(1)
    
    # Determine output path
    if args.output:
        output_path = Path(args.output)
    else:
        output_path = engine_path.with_name(engine_path.stem + "_obf.sv")
    
    print(f"Obfuscating: {engine_path}")
    print(f"Output: {output_path}")
    
    # Read engine content
    content = engine_path.read_text()
    
    # Generate license hash
    engine_name = engine_path.stem
    license_hash = generate_license_hash(engine_name, args.secret_key)
    print(f"License hash: {license_hash}")
    
    # Apply obfuscation
    if not args.no_yosys:
        print("Running Yosys synthesis obfuscation...")
        obfuscate_with_yosys(str(engine_path), str(output_path))
        content = output_path.read_text()
    
    print("Applying signal obfuscation...")
    content = obfuscate_signals(content, args.seed)
    
    print("Adding license check...")
    content = add_license_check(content, license_hash)
    
    # Write output
    output_path.write_text(content)
    print(f"Obfuscated engine written to: {output_path}")
    print(f"\nTo use this engine, provide the license key:")
    print(f"  LICENSE_KEY = 256'h{license_hash}")


if __name__ == "__main__":
    main()
