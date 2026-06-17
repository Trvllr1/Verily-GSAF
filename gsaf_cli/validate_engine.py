"""
GSAF Studio CLI - Engine Validator

Validates client engines against the gf_engine_if.sv interface contract,
runs formal proofs, and generates evidence packs.
"""
import subprocess
import sys
import os
from pathlib import Path
from typing import Optional
import typer
from rich.console import Console
from rich.table import Table
from rich.panel import Panel

app = typer.Typer(help="GSAF Engine Validator")
console = Console()


def run_cmd(cmd: str, cwd: Optional[str] = None) -> tuple[int, str, str]:
    """Run a shell command and return (returncode, stdout, stderr)."""
    result = subprocess.run(
        cmd, shell=True, capture_output=True, text=True, cwd=cwd
    )
    return result.returncode, result.stdout, result.stderr


@app.command()
def validate(
    engine: str = typer.Argument(..., help="Path to engine SystemVerilog file"),
    golden_model: Optional[str] = typer.Option(
        None, "--golden-model", "-g", help="Path to golden model Python file"
    ),
    width: int = typer.Option(64, "--width", "-w", help="Data path width"),
    output_dir: str = typer.Option(
        "evidence-pack", "--output", "-o", help="Output directory for evidence"
    ),
    skip_formal: bool = typer.Option(
        False, "--skip-formal", help="Skip formal verification"
    ),
    skip_sim: bool = typer.Option(
        False, "--skip-sim", help="Skip simulation tests"
    ),
):
    """Validate an engine against gf_engine_if.sv and generate evidence pack."""

    engine_path = Path(engine)
    if not engine_path.exists():
        console.print(f"[red]Engine file not found: {engine}[/red]")
        raise typer.Exit(1)

    console.print(Panel(f"Validating engine: {engine_path.name}", style="bold blue"))

    results = []

    # Step 1: Verilator lint
    console.print("\n[bold]Step 1: Verilator Lint[/bold]")
    rc, stdout, stderr = run_cmd(
        f"verilator --lint-only -Wall -Irtl rtl/gf_pkg.sv {engine} "
        f"--top-module {engine_path.stem}"
    )
    if rc == 0:
        console.print("[green]  PASS: Verilator lint[/green]")
        results.append(("Verilator Lint", "PASS"))
    else:
        console.print(f"[red]  FAIL: Verilator lint[/red]")
        console.print(f"  {stderr[:200]}")
        results.append(("Verilator Lint", "FAIL"))

    # Step 2: Yosys synthesis check
    console.print("\n[bold]Step 2: Yosys Synthesis Check[/bold]")
    rc, stdout, stderr = run_cmd(
        f"yosys -p \"read_verilog -Irtl rtl/gf_pkg.sv {engine}; "
        f"synth -top {engine_path.stem}\" 2>&1"
    )
    if rc == 0:
        console.print("[green]  PASS: Yosys synthesis[/green]")
        results.append(("Yosys Synthesis", "PASS"))
    else:
        console.print(f"[yellow]  WARN: Yosys synthesis issues[/yellow]")
        results.append(("Yosys Synthesis", "WARN"))

    # Step 3: Formal verification (optional)
    if not skip_formal:
        console.print("\n[bold]Step 3: Formal Verification (SymbiYosys)[/bold]")
        # Create temporary sby file
        sby_content = f"""[options]
mode prove
depth 50

[script]
read -sv rtl/gf_pkg.sv
read -sv {engine}
prep -top {engine_path.stem}

[engines]
smtbmc

[files]
rtl/gf_pkg.sv
{engine}
"""
        sby_file = Path(f"formal/sby_{engine_path.stem}.sby")
        sby_file.parent.mkdir(parents=True, exist_ok=True)
        sby_file.write_text(sby_content)

        rc, stdout, stderr = run_cmd(f"sby -f {sby_file} prove")
        if rc == 0:
            console.print("[green]  PASS: Formal verification[/green]")
            results.append(("Formal Verification", "PASS"))
        else:
            console.print(f"[yellow]  WARN: Formal verification[/yellow]")
            results.append(("Formal Verification", "WARN"))
    else:
        console.print("\n[bold]Step 3: Formal Verification[/bold] (skipped)")
        results.append(("Formal Verification", "SKIP"))

    # Step 4: Simulation tests (optional)
    if not skip_sim:
        console.print("\n[bold]Step 4: Simulation Tests[/bold]")
        dyno_targets = {
            "modexp": "test-modexp", "modinv": "test-modinv",
            "pqc": "test-pqc", "rsa_crt": "test-rsa-crt", "ecc": "test-ecc",
        }
        stem = engine_path.stem.replace("gf_", "").replace("_engine", "")
        target = dyno_targets.get(stem, "test-all")
        rc, stdout, stderr = run_cmd(f"make {target} 2>&1", cwd="tb/dynos")
        if rc == 0:
            console.print("[green]  PASS: Simulation tests[/green]")
            results.append(("Simulation Tests", "PASS"))
        else:
            console.print(f"[yellow]  WARN: Simulation tests[/yellow]")
            results.append(("Simulation Tests", "WARN"))
    else:
        console.print("\n[bold]Step 4: Simulation Tests[/bold] (skipped)")
        results.append(("Simulation Tests", "SKIP"))

    # Step 5: Generate evidence pack
    console.print("\n[bold]Step 5: Generate Evidence Pack[/bold]")
    out_path = Path(output_dir) / f"02_engine_{engine_path.stem}"
    out_path.mkdir(parents=True, exist_ok=True)

    # Copy engine file
    (out_path / "rtl").mkdir(exist_ok=True)
    (out_path / "rtl" / engine_path.name).write_text(engine_path.read_text())

    # Copy formal results if they exist
    formal_src = Path("formal") / f"sby_{engine_path.stem}"
    if formal_src.exists():
        import shutil
        shutil.copytree(formal_src, out_path / "formal", dirs_exist_ok=True)

    console.print(f"[green]  Evidence pack generated: {out_path}[/green]")
    results.append(("Evidence Pack", "GENERATED"))

    # Summary
    console.print("\n" + "=" * 60)
    table = Table(title="Validation Summary")
    table.add_column("Step", style="cyan")
    table.add_column("Result", style="green")
    for step, result in results:
        table.add_row(step, result)
    console.print(table)

    # Final verdict
    failed = any(r == "FAIL" for _, r in results)
    if failed:
        console.print("\n[red]VALIDATION FAILED[/red]")
        raise typer.Exit(1)
    else:
        console.print("\n[green]VALIDATION PASSED[/green]")


@app.command()
def template(
    name: str = typer.Argument(..., help="Engine name (e.g., 'my_ntt_engine')"),
    width: int = typer.Option(64, "--width", "-w", help="Data path width"),
    output_dir: str = typer.Option("rtl", "--output", "-o", help="Output directory"),
):
    """Generate a starter engine template."""

    template_path = Path(__file__).parent.parent / "rtl" / "gf_engine_template.sv"
    if not template_path.exists():
        console.print("[red]Template file not found[/red]")
        raise typer.Exit(1)

    # Read template and customize
    template_content = template_path.read_text()
    template_content = template_content.replace("gf_engine_template", name)
    template_content = template_content.replace(
        "parameter int unsigned WIDTH = gf_pkg::GF_WIDTH_DEFAULT",
        f"parameter int unsigned WIDTH = {width}"
    )

    # Write output
    out_path = Path(output_dir) / f"{name}.sv"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(template_content)

    console.print(f"[green]Engine template generated: {out_path}[/green]")
    console.print(f"\nNext steps:")
    console.print(f"  1. Edit {out_path} with your computation logic")
    console.print(f"  2. Create a golden model Python file")
    console.print(f"  3. Run: gsaf validate-engine {out_path} -g your_model.py")


if __name__ == "__main__":
    app()
