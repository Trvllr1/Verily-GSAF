"""GSAF Studio CLI - Explore Command"""
import typer
from rich.console import Console
from rich.table import Table
from pathlib import Path

app = typer.Typer(help="List RTL modules and interfaces")
console = Console()


@app.command()
def main(
    module: str = typer.Option(None, "--module", "-m", help="Specific module to explore"),
    verbose: bool = typer.Option(False, "--verbose", "-v", help="Show detailed info"),
):
    """List RTL modules, their interfaces, and formal verification status."""
    
    rtl_dir = Path("rtl")
    if not rtl_dir.exists():
        console.print("[red]RTL directory not found[/red]")
        raise typer.Exit(1)
    
    # Find all SV files
    sv_files = sorted(rtl_dir.glob("*.sv"))
    
    if module:
        # Filter to specific module
        sv_files = [f for f in sv_files if module in f.stem]
    
    table = Table(title="GSAF RTL Modules")
    table.add_column("Module", style="cyan")
    table.add_column("Type", style="green")
    table.add_column("Lines", style="yellow")
    table.add_column("Interface", style="blue")
    
    for sv_file in sv_files:
        content = sv_file.read_text()
        lines = len(content.splitlines())
        
        # Determine type
        if "module" in content and "interface" not in content:
            mod_type = "RTL"
        elif "interface" in content:
            mod_type = "Interface"
        elif "package" in content:
            mod_type = "Package"
        else:
            mod_type = "Other"
        
        # Determine interface
        if "gf_engine_if" in content:
            interface = "Engine IF"
        elif "AXI" in content or "axil" in content.lower():
            interface = "AXI4-Lite"
        elif "valid" in content and "ready" in content:
            interface = "Valid/Ready"
        else:
            interface = "Custom"
        
        table.add_row(sv_file.stem, mod_type, str(lines), interface)
    
    console.print(table)
    
    if verbose:
        console.print(f"\n[bold]Total modules:[/bold] {len(sv_files)}")


if __name__ == "__main__":
    app()
