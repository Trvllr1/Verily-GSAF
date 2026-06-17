"""
GSAF Studio CLI - Main Entry Point

Commands:
  gsaf explore      - List RTL modules and interfaces
  gsaf architect    - Validate architecture constraints
  gsaf verify       - Run formal + simulation verification
  gsaf assure       - Generate evidence pack
  gsaf validate-engine - Validate client engines
  gsaf template     - Generate engine template
  gsaf license      - Manage engine licensing
  gsaf fpga         - FPGA synthesis and testing
"""
import typer
from rich.console import Console

app = typer.Typer(
    name="gsaf",
    help="GSAF Studio - Constant-time cryptographic arithmetic fabric verification",
    no_args_is_help=True,
)
console = Console()


# Import subcommands
from .explore import app as explore_app
from .architect import app as architect_app
from .verify import app as verify_app
from .assure import app as assure_app
from .validate_engine import app as validate_engine_app
from .license import app as license_app
from .fpga import app as fpga_app


# Register subcommands
app.add_typer(explore_app, name="explore", help="List RTL modules and interfaces")
app.add_typer(architect_app, name="architect", help="Validate architecture constraints")
app.add_typer(verify_app, name="verify", help="Run formal + simulation verification")
app.add_typer(assure_app, name="assure", help="Generate evidence pack")
app.add_typer(validate_engine_app, name="validate-engine", help="Validate client engines")
app.add_typer(validate_engine_app, name="template", help="Generate engine template")
app.add_typer(license_app, name="license", help="Manage engine licensing")
app.add_typer(fpga_app, name="fpga", help="FPGA synthesis and testing")


@app.command()
def version():
    """Show GSAF Studio version."""
    console.print("[bold]GSAF Studio[/bold] v0.1.0")
    console.print("Constant-time cryptographic arithmetic fabric verification")


if __name__ == "__main__":
    app()
