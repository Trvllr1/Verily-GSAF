"""GSAF Studio CLI - Verify Command"""
import subprocess
from typing import List, Optional
import typer
from rich.console import Console
from rich.table import Table

app = typer.Typer(help="Run formal + simulation verification")
console = Console()

ENGINE_GOLDEN_MODELS = {
    "modexp": "python model/golden_model.py",
    "modinv": "python model/golden_model.py",
    "pqc": "python model/pqc_ntt_model.py",
    "rsa-crt": "python model/rsa_crt_model.py",
    "ecc": "python model/ecc_model.py",
}

ENGINE_DYNO_TARGETS = {
    "modexp": "test-modexp",
    "modinv": "test-modinv",
    "pqc": "test-pqc",
    "rsa-crt": "test-rsa-crt",
    "ecc": "test-ecc",
}


@app.command(name="main")
def verify(
    formal: bool = typer.Option(False, "--formal", help="Run formal verification only"),
    simulation: bool = typer.Option(False, "--simulation", help="Run simulation only"),
    all: bool = typer.Option(True, "--all/--no-all", help="Run all verification"),
    engine: Optional[str] = typer.Option(
        None, "--engine", "-e",
        help="Comma-separated engines to verify (modexp,modinv,pqc,rsa-crt,ecc)"
    ),
):
    """Run formal verification and simulation, collect results."""

    console.print("[bold]GSAF Verification[/bold]\n")

    engines = [e.strip() for e in engine.split(",")] if engine else list(ENGINE_DYNO_TARGETS.keys())
    results = []

    # Step 1: Golden model self-tests
    if all or not (formal or simulation):
        console.print("[bold]Golden Model Self-Tests[/bold]")
        seen_models = set()
        for eng in engines:
            model_cmd = ENGINE_GOLDEN_MODELS.get(eng)
            if not model_cmd or model_cmd in seen_models:
                continue
            seen_models.add(model_cmd)
            console.print(f"  Running: {model_cmd}")
            result = subprocess.run(model_cmd, shell=True, capture_output=True, text=True)
            label = model_cmd.split("/")[-1]
            if result.returncode == 0:
                console.print(f"    [green]PASS[/green]")
                results.append((f"Golden: {label}", "PASS"))
            else:
                console.print(f"    [red]FAIL[/red]")
                if result.stderr:
                    console.print(f"    {result.stderr[:200]}")
                results.append((f"Golden: {label}", "FAIL"))

    # Step 2: Verilator lint
    if all or not (formal or simulation):
        console.print("\n[bold]Lint[/bold]")
        lint_result = subprocess.run(
            "make lint", shell=True, capture_output=True, text=True
        )
        if lint_result.returncode == 0:
            console.print("  [green]PASS[/green]")
            results.append(("Lint", "PASS"))
        else:
            console.print("  [red]FAIL[/red]")
            results.append(("Lint", "FAIL"))

    # Step 3: Formal verification
    if all or formal:
        console.print("\n[bold]Formal Verification[/bold]")
        formal_result = subprocess.run(
            "make formal", shell=True, capture_output=True, text=True
        )
        if formal_result.returncode == 0:
            console.print("  [green]PASS[/green]")
            results.append(("Formal", "PASS"))
        else:
            console.print("  [red]FAIL[/red]")
            results.append(("Formal", "FAIL"))

    # Step 4: Simulation (dyno tests)
    if all or simulation:
        console.print("\n[bold]Simulation (Dyno Tests)[/bold]")
        for eng in engines:
            target = ENGINE_DYNO_TARGETS.get(eng)
            if not target:
                console.print(f"  [yellow]SKIP: {eng} (no dyno target)[/yellow]")
                results.append((f"Sim: {eng}", "SKIP"))
                continue

            console.print(f"  Running: make {target}")
            sim_result = subprocess.run(
                f"make {target}", shell=True, capture_output=True, text=True,
                cwd="tb/dynos"
            )
            if sim_result.returncode == 0:
                console.print(f"    [green]PASS[/green]")
                results.append((f"Sim: {eng}", "PASS"))
            else:
                console.print(f"    [red]FAIL[/red]")
                results.append((f"Sim: {eng}", "FAIL"))

    # Summary
    table = Table(title="Verification Summary")
    table.add_column("Step", style="cyan")
    table.add_column("Result", style="green")

    for name, result in results:
        table.add_row(name, result)

    console.print("\n" + "=" * 50)
    console.print(table)

    failed = any(r == "FAIL" for _, r in results)
    if failed:
        console.print("\n[red]VERIFICATION FAILED[/red]")
        raise typer.Exit(1)
    else:
        console.print("\n[green]VERIFICATION PASSED[/green]")


if __name__ == "__main__":
    app()
