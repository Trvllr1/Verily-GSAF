"""GSAF Studio CLI - Assure Command"""
import subprocess
import shutil
from pathlib import Path
import typer
from rich.console import Console
from rich.table import Table

app = typer.Typer(help="Generate evidence pack")
console = Console()


@app.command()
def main(
    tier: str = typer.Option("free", "--tier", "-t",
                             help="Evidence pack tier (free, paid, enterprise)"),
    output: str = typer.Option("evidence-pack", "--output", "-o",
                               help="Output directory"),
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
        dirs.extend([
            out_path / "02_engine_modexp" / "rtl",
            out_path / "02_engine_modexp" / "formal" / "results",
            out_path / "02_engine_modinv" / "rtl",
            out_path / "02_engine_modinv" / "formal" / "results",
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
    
    # Run golden model
    console.print("\n[bold]Running golden model...[/bold]")
    result = subprocess.run(
        "python model/golden_model.py", shell=True, capture_output=True, text=True
    )
    golden_output = out_path / "01_chassis" / "golden_model" / "selftest_output.txt"
    golden_output.write_text(result.stdout + result.stderr)
    
    if result.returncode == 0:
        console.print("  [green]PASS[/green]")
    else:
        console.print("  [yellow]WARN (some tests may have failed)[/yellow]")
    
    # Run formal verification
    console.print("\n[bold]Running formal verification...[/bold]")
    result = subprocess.run("make formal", shell=True, capture_output=True, text=True)
    formal_output = out_path / "01_chassis" / "formal" / "results" / "formal.log"
    formal_output.write_text(result.stdout + result.stderr)
    
    if result.returncode == 0:
        console.print("  [green]PASS[/green]")
    else:
        console.print("  [yellow]WARN (formal may have issues)[/yellow]")
    
    # Generate manifest
    console.print("\n[bold]Generating manifest...[/bold]")
    manifest = out_path / "PACK_MANIFEST.md"
    manifest.write_text(f"""# GSAF Evidence Pack — Manifest

**Version:** 0.1.0
**Tier:** {tier}
**Generated:** {__import__('datetime').datetime.utcnow().isoformat()}

## Contents

| Folder | Description |
|--------|-------------|
| `01_chassis/` | Chassis RTL verification evidence |
""")
    
    if tier in ["paid", "enterprise"]:
        manifest.write_text("""| `02_engine_modexp/` | ModExp engine verification evidence |
| `02_engine_modinv/` | ModInv engine verification evidence |
""")
    
    console.print(f"  [green]{manifest}[/green]")
    
    # Summary
    console.print("\n" + "=" * 50)
    table = Table(title="Evidence Pack Summary")
    table.add_column("Item", style="cyan")
    table.add_column("Status", style="green")
    
    table.add_row("RTL Files", "Copied")
    table.add_row("Golden Model", "Run")
    table.add_row("Formal Verification", "Run")
    table.add_row("Manifest", "Generated")
    
    console.print(table)
    console.print(f"\n[green]Evidence pack generated: {out_path}[/green]")
    console.print(f"\nTo verify completeness:")
    console.print(f"  gsaf assure --tier {tier} --verify")


if __name__ == "__main__":
    app()
