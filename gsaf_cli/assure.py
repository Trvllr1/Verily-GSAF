"""GSAF Studio CLI - Assure Command"""
import subprocess
import shutil
from pathlib import Path
from typing import Optional
import typer
from rich.console import Console
from rich.table import Table

app = typer.Typer(help="Generate evidence pack")
console = Console()

ALL_ENGINES = ["modexp", "modinv", "pqc", "rsa_crt", "ecc"]

GOLDEN_MODEL_CMDS = [
    ("golden_model.py", "python model/golden_model.py"),
    ("pqc_ntt_model.py", "python model/pqc_ntt_model.py"),
    ("rsa_crt_model.py", "python model/rsa_crt_model.py"),
    ("ecc_model.py", "python model/ecc_model.py"),
]


@app.command(name="main")
def assure(
    tier: str = typer.Option("free", "--tier", "-t",
                             help="Evidence pack tier (free, paid, enterprise)"),
    output: str = typer.Option("evidence-pack", "--output", "-o",
                               help="Output directory"),
    verify: bool = typer.Option(False, "--verify", help="Verify pack completeness after generation"),
):
    """Generate evidence pack and validate completeness."""

    console.print(f"[bold]GSAF Evidence Pack Generation (Tier: {tier})[/bold]\n")

    out_path = Path(output)

    # Create directory structure
    dirs = [
        out_path / "01_chassis" / "rtl",
        out_path / "01_chassis" / "formal" / "results",
        out_path / "01_chassis" / "simulation",
        out_path / "01_chassis" / "golden_model",
    ]

    if tier in ["paid", "enterprise"]:
        for engine in ALL_ENGINES:
            dirs.extend([
                out_path / f"02_engine_{engine}" / "rtl",
                out_path / f"02_engine_{engine}" / "formal" / "results",
            ])

    for d in dirs:
        d.mkdir(parents=True, exist_ok=True)

    # Copy RTL files
    console.print("[bold]Copying RTL files...[/bold]")
    rtl_src = Path("rtl")
    rtl_dst = out_path / "01_chassis" / "rtl"
    for sv_file in rtl_src.glob("*.sv"):
        shutil.copy2(sv_file, rtl_dst / sv_file.name)
        console.print(f"  {sv_file.name}")

    # Run golden models
    console.print("\n[bold]Running golden models...[/bold]")
    golden_dir = out_path / "01_chassis" / "golden_model"
    for model_name, model_cmd in GOLDEN_MODEL_CMDS:
        result = subprocess.run(model_cmd, shell=True, capture_output=True, text=True)
        output_file = golden_dir / model_name.replace(".py", "_output.txt")
        output_file.write_text(result.stdout + result.stderr)

        if result.returncode == 0:
            console.print(f"  [green]PASS[/green] {model_name}")
        else:
            console.print(f"  [yellow]WARN[/yellow] {model_name}")

    # Run lint
    console.print("\n[bold]Running lint...[/bold]")
    lint_result = subprocess.run("make lint", shell=True, capture_output=True, text=True)
    lint_output = out_path / "01_chassis" / "simulation" / "lint.log"
    lint_output.write_text(lint_result.stdout + lint_result.stderr)

    if lint_result.returncode == 0:
        console.print("  [green]PASS[/green]")
    else:
        console.print("  [yellow]WARN[/yellow]")

    # Run formal verification
    console.print("\n[bold]Running formal verification...[/bold]")
    formal_result = subprocess.run("make formal", shell=True, capture_output=True, text=True)
    formal_output = out_path / "01_chassis" / "formal" / "results" / "formal.log"
    formal_output.write_text(formal_result.stdout + formal_result.stderr)

    if formal_result.returncode == 0:
        console.print("  [green]PASS[/green]")
    else:
        console.print("  [yellow]WARN[/yellow]")

    # Run simulation
    console.print("\n[bold]Running simulation...[/bold]")
    sim_result = subprocess.run("make sim", shell=True, capture_output=True, text=True)
    sim_output = out_path / "01_chassis" / "simulation" / "sim.log"
    sim_output.write_text(sim_result.stdout + sim_result.stderr)

    if sim_result.returncode == 0:
        console.print("  [green]PASS[/green]")
    else:
        console.print("  [yellow]WARN[/yellow]")

    # Copy engine-specific evidence for paid/enterprise
    if tier in ["paid", "enterprise"]:
        console.print("\n[bold]Copying engine evidence...[/bold]")
        for engine in ALL_ENGINES:
            engine_rtl_dst = out_path / f"02_engine_{engine}" / "rtl"
            # Copy engine-specific RTL if it exists
            engine_rtl = rtl_src / f"gf_{engine}_engine.sv"
            if engine_rtl.exists():
                shutil.copy2(engine_rtl, engine_rtl_dst / engine_rtl.name)
                console.print(f"  {engine_rtl.name}")

    # Generate manifest
    console.print("\n[bold]Generating manifest...[/bold]")
    manifest = out_path / "PACK_MANIFEST.md"

    manifest_content = f"""# GSAF Evidence Pack — Manifest

**Version:** 0.1.0
**Tier:** {tier}
**Generated:** {__import__('datetime').datetime.utcnow().isoformat()}

## Contents

| Folder | Description |
|--------|-------------|
| `01_chassis/` | Chassis RTL verification evidence |
"""
    if tier in ["paid", "enterprise"]:
        for engine in ALL_ENGINES:
            manifest_content += f"| `02_engine_{engine}/` | {engine} engine verification evidence |\n"

    manifest.write_text(manifest_content)
    console.print(f"  [green]{manifest}[/green]")

    # Summary
    console.print("\n" + "=" * 50)
    table = Table(title="Evidence Pack Summary")
    table.add_column("Item", style="cyan")
    table.add_column("Status", style="green")

    table.add_row("RTL Files", "Copied")
    table.add_row("Golden Models", "Run")
    table.add_row("Lint", "Run")
    table.add_row("Formal Verification", "Run")
    table.add_row("Simulation", "Run")
    table.add_row("Manifest", "Generated")

    if tier in ["paid", "enterprise"]:
        table.add_row("Engine Evidence", f"{len(ALL_ENGINES)} engines")

    console.print(table)
    console.print(f"\n[green]Evidence pack generated: {out_path}[/green]")

    # Verify completeness if requested
    if verify:
        _verify_pack(out_path, tier)


def _verify_pack(out_path: Path, tier: str):
    """Verify evidence pack completeness."""
    console.print("\n[bold]Verifying evidence pack completeness...[/bold]")

    issues = []

    # Check chassis RTL
    chassis_rtl = out_path / "01_chassis" / "rtl"
    if not chassis_rtl.exists() or not list(chassis_rtl.glob("*.sv")):
        issues.append("Missing chassis RTL files")

    # Check golden model outputs
    golden_dir = out_path / "01_chassis" / "golden_model"
    for model_name, _ in GOLDEN_MODEL_CMDS:
        output_file = golden_dir / model_name.replace(".py", "_output.txt")
        if not output_file.exists():
            issues.append(f"Missing golden model output: {model_name}")

    # Check manifest
    manifest = out_path / "PACK_MANIFEST.md"
    if not manifest.exists():
        issues.append("Missing PACK_MANIFEST.md")

    # Check engine packs for paid/enterprise
    if tier in ["paid", "enterprise"]:
        for engine in ALL_ENGINES:
            engine_dir = out_path / f"02_engine_{engine}"
            if not engine_dir.exists():
                issues.append(f"Missing engine pack: {engine}")

    if issues:
        console.print("[red]Incomplete evidence pack:[/red]")
        for issue in issues:
            console.print(f"  - {issue}")
        raise typer.Exit(1)
    else:
        console.print("[green]Evidence pack is complete[/green]")


if __name__ == "__main__":
    app()
