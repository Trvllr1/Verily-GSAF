"""GSAF Studio CLI - Verify Command"""
import subprocess
import typer
from rich.console import Console
from rich.table import Table

app = typer.Typer(help="Run formal + simulation verification")
console = Console()


@app.command()
def main(
    formal: bool = typer.Option(False, "--formal", help="Run formal verification only"),
    simulation: bool = typer.Option(False, "--simulation", help="Run simulation only"),
    all: bool = typer.Option(True, "--all", help="Run all verification"),
):
    """Run formal verification and simulation, collect results."""
    
    console.print("[bold]GSAF Verification[/bold]\n")
    
    results = []
    
    # Run verification steps
    steps = []
    if all or formal:
        steps.append(("Formal Verification", "make formal"))
    if all or simulation:
        steps.append(("Simulation", "make sim"))
        steps.append(("Golden Model", "python model/golden_model.py"))
    
    for name, cmd in steps:
        console.print(f"[bold]Running: {name}[/bold]")
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        
        if result.returncode == 0:
            console.print(f"  [green]PASS[/green]")
            results.append((name, "PASS"))
        else:
            console.print(f"  [red]FAIL[/red]")
            results.append((name, "FAIL"))
    
    # Summary
    table = Table(title="Verification Summary")
    table.add_column("Step", style="cyan")
    table.add_column("Result", style="green")
    
    for name, result in results:
        table.add_row(name, result)
    
    console.print("\n" + "=" * 50)
    console.print(table)
    
    # Final verdict
    failed = any(r == "FAIL" for _, r in results)
    if failed:
        console.print("\n[red]VERIFICATION FAILED[/red]")
        raise typer.Exit(1)
    else:
        console.print("\n[green]VERIFICATION PASSED[/green]")


if __name__ == "__main__":
    app()
