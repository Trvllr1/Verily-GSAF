"""GSAF Studio CLI - Architect Command"""
import typer
from rich.console import Console
from rich.table import Table
from pathlib import Path

app = typer.Typer(help="Validate architecture constraints")
console = Console()


@app.command(name="main")
def architect(
    width: int = typer.Option(64, "--width", "-w", help="Data path width"),
    banks: int = typer.Option(4, "--banks", "-b", help="Number of operand banks"),
    multipliers: int = typer.Option(1, "--multipliers", "-m", help="Number of multiplier lanes"),
    check_all: bool = typer.Option(False, "--check-all", help="Check all constraints"),
):
    """Validate architecture constraints (WIDTH, bank count, multiplier count, etc.)."""
    
    console.print("[bold]GSAF Architecture Validation[/bold]\n")
    
    # Load parameters from gf_pkg.sv
    pkg_path = Path("rtl/gf_pkg.sv")
    if not pkg_path.exists():
        console.print("[red]gf_pkg.sv not found[/red]")
        raise typer.Exit(1)
    
    content = pkg_path.read_text()
    
    # Parse constraints
    constraints = {
        "WIDTH": {"value": width, "min": 8, "max": 4096},
        "NUM_OPERAND_BANKS": {"value": banks, "min": 1, "max": 8},
        "NUM_MULTIPLIERS": {"value": multipliers, "min": 1, "max": 8},
    }
    
    # Validate
    table = Table(title="Architecture Constraints")
    table.add_column("Parameter", style="cyan")
    table.add_column("Value", style="green")
    table.add_column("Range", style="yellow")
    table.add_column("Status", style="blue")
    
    all_pass = True
    for param, info in constraints.items():
        value = info["value"]
        min_val = info["min"]
        max_val = info["max"]
        
        if min_val <= value <= max_val:
            status = "[green]PASS[/green]"
        else:
            status = "[red]FAIL[/red]"
            all_pass = False
        
        table.add_row(param, str(value), f"{min_val}-{max_val}", status)
    
    console.print(table)
    
    # Derived constraints
    console.print("\n[bold]Derived Constraints:[/bold]")
    
    # Check WIDTH alignment
    if width % 32 == 0:
        console.print(f"  [green]WIDTH={width} is 32-bit aligned[/green]")
    else:
        console.print(f"  [yellow]WIDTH={width} is not 32-bit aligned (may cause issues)[/yellow]")
    
    # Check operand bank sizing
    bank_size = width * 3  # A, B, M operands
    console.print(f"  Bank size: {bank_size} bits ({bank_size // 8} bytes)")
    
    # Check multiplier lanes
    if multipliers >= 1:
        console.print(f"  [green]At least 1 multiplier lane available[/green]")
    else:
        console.print(f"  [red]No multiplier lanes available[/red]")
        all_pass = False
    
    if all_pass:
        console.print("\n[green]All constraints satisfied[/green]")
    else:
        console.print("\n[red]Some constraints failed[/red]")
        raise typer.Exit(1)


if __name__ == "__main__":
    app()
