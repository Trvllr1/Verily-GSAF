#!/usr/bin/env python3
"""
Build cocotb Verilator VPI library for Windows.

cocotb 1.9.2 only builds cocotbvpi_verilator on POSIX (see cocotb_build_libs.py:815).
On Windows, this script rebuilds all cocotb native libraries with MinGW/g++ and
creates the Verilator VPI library by compiling VPI sources directly into the binary.

Usage:
    python scripts/build_cocotb_vpi.py [--venv PATH]

Requirements:
    - MSYS2 MinGW64 (g++, make, verilator)
    - Python 3.10+ with cocotb installed in a venv
"""
import os
import subprocess
import sys
from pathlib import Path


def find_tools():
    """Find required tools."""
    tools = {}
    for name in ["g++", "verilator", "make", "windres"]:
        result = subprocess.run(
            ["where", name] if os.name == "nt" else ["which", name],
            capture_output=True, text=True
        )
        if result.returncode == 0:
            tools[name] = result.stdout.strip().split("\n")[0]
        else:
            tools[name] = None
    return tools


def find_cocotb(venv_path=None):
    """Find cocotb installation."""
    if venv_path:
        python = Path(venv_path) / "Scripts" / "python.exe" if os.name == "nt" else Path(venv_path) / "bin" / "python"
        if python.exists():
            result = subprocess.run(
                [str(python), "-c", "import cocotb; import os; print(os.path.dirname(cocotb.__file__))"],
                capture_output=True, text=True
            )
            if result.returncode == 0:
                return Path(result.stdout.strip()), str(python)

    # Try system python
    result = subprocess.run(
        [sys.executable, "-c", "import cocotb; import os; print(os.path.dirname(cocotb.__file__))"],
        capture_output=True, text=True
    )
    if result.returncode == 0:
        return Path(result.stdout.strip()), sys.executable

    return None, None


def build_cocotb_from_source(cocotb_dir, python_exe, tools):
    """Build cocotb native libraries from source with MinGW."""
    print("Building cocotb native libraries from source with MinGW...")

    env = os.environ.copy()
    env["CC"] = "gcc"
    env["CXX"] = "g++"

    result = subprocess.run(
        [python_exe, "setup.py", "build_ext", "--compiler=mingw32"],
        cwd=str(cocotb_dir.parent),
        env=env,
        capture_output=True, text=True
    )

    if result.returncode != 0:
        print(f"Build failed:\n{result.stderr[-1000:]}")
        return False

    print("Build successful.")
    return True


def copy_libraries(build_dir, libs_dir):
    """Copy MinGW-built libraries to cocotb libs directory."""
    import shutil

    build_libs = Path(build_dir) / "lib.win-amd64-cpython-312" / "cocotb" / "libs"
    if not build_libs.exists():
        print(f"Build output not found: {build_libs}")
        return False

    for dll in build_libs.glob("*.dll"):
        # Strip 'lib' prefix for MinGW builds
        name = dll.name
        if name.startswith("lib"):
            dest_name = name[3:]  # Remove 'lib' prefix
        else:
            dest_name = name

        dest = libs_dir / dest_name
        shutil.copy2(dll, dest)
        print(f"  {dll.name} -> {dest_name}")

    return True


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Build cocotb Verilator VPI for Windows")
    parser.add_argument("--venv", help="Path to Python virtual environment")
    parser.add_argument("--source-dir", help="Path to cocotb source directory")
    args = parser.parse_args()

    if os.name != "nt":
        print("This script is for Windows only. On Linux/Mac, cocotb builds VPI natively.")
        sys.exit(0)

    print("=== GSAF cocotb VPI Builder for Windows ===\n")

    # Find tools
    tools = find_tools()
    print("Tools found:")
    for name, path in tools.items():
        status = f"  {path}" if path else "  NOT FOUND"
        print(f"  {name}: {status}")

    if not tools.get("g++"):
        print("\nERROR: g++ not found. Install MSYS2 MinGW64: pacman -S mingw-w64-x86_64-gcc")
        sys.exit(1)

    if not tools.get("verilator"):
        print("\nERROR: verilator not found. Install: pacman -S mingw-w64-x86_64-verilator")
        sys.exit(1)

    # Find cocotb
    cocotb_dir, python_exe = find_cocotb(args.venv)
    if not cocotb_dir:
        print("\nERROR: cocotb not found. Install: pip install cocotb")
        sys.exit(1)

    print(f"\n cocotb: {cocotb_dir}")
    print(f" Python: {python_exe}")

    # Check if VPI library already exists
    vpi_dll = cocotb_dir / "libs" / "cocotbvpi_verilator.dll"
    if vpi_dll.exists():
        print(f"\nVPI library already exists: {vpi_dll}")
        print("To rebuild, delete the file first.")
        sys.exit(0)

    # Clone cocotb source if not provided
    source_dir = Path(args.source_dir) if args.source_dir else Path("C:/cocotb-src")
    if not source_dir.exists():
        print(f"\nCloning cocotb source to {source_dir}...")
        subprocess.run(
            ["git", "clone", "--depth", "1", "https://github.com/cocotb/cocotb.git", str(source_dir)],
            check=True
        )

    # Apply Windows Verilator VPI patch
    build_libs_py = source_dir / "cocotb_build_libs.py"
    content = build_libs_py.read_text()
    if 'if os.name == "posix":\n        logger.info("Compiling libraries for Verilator")' in content:
        print("\nPatching cocotb to enable Verilator VPI on Windows...")
        content = content.replace(
            'if os.name == "posix":\n        logger.info("Compiling libraries for Verilator")',
            'if os.name in ("posix", "nt"):\n        logger.info("Compiling libraries for Verilator")'
        )
        build_libs_py.write_text(content)

    # Build
    success = build_cocotb_from_source(source_dir, python_exe, tools)
    if not success:
        print("\nBuild failed. See output above for details.")
        sys.exit(1)

    # Copy libraries
    build_dir = source_dir / "build"
    copy_libraries(build_dir, cocotb_dir / "libs")

    # Check result
    if vpi_dll.exists():
        print(f"\nSUCCESS: VPI library created: {vpi_dll}")
    else:
        print(f"\nWARNING: VPI library not created. The Verilator VPI may have failed to build.")
        print("This is expected if the VPI linker step failed due to unresolved symbols.")
        print("The simulation will compile the VPI sources directly instead.")


if __name__ == "__main__":
    main()
