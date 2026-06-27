"""
GSAF Studio CLI - License Manager

Manages engine licensing, including key generation, validation, and evidence pack signing.
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

app = typer.Typer(help="GSAF License Manager")
console = Console()


@app.command()
def generate(
    engine: str = typer.Argument(..., help="Engine name to generate license for"),
    secret_key: str = typer.Option("verily-gsaf-2026", "--key", "-k",
                                   help="Secret key for license generation"),
    output: str = typer.Option("licenses", "--output", "-o",
                               help="Output directory for license files"),
):
    """Generate a license key for an engine."""
    import hashlib
    
    # Generate license hash
    data = f"{engine}:{secret_key}"
    license_hash = hashlib.sha256(data.encode()).hexdigest()[:64]
    
    # Create output directory
    out_path = Path(output)
    out_path.mkdir(parents=True, exist_ok=True)
    
    # Write license file
    license_file = out_path / f"{engine}.license"
    license_file.write_text(f"""# GSAF Engine License
# Engine: {engine}
# Generated: {__import__('datetime').datetime.utcnow().isoformat()}

LICENSE_KEY = 256'h{license_hash}
""")
    
    console.print(f"[green]License generated: {license_file}[/green]")
    console.print(f"\nLicense key: [bold]{license_hash}[/bold]")
    console.print(f"\nTo use this license:")
    console.print(f"  1. Add to your engine instantiation:")
    console.print(f"     .LICENSE_KEY(256'h{license_hash})")
    console.print(f"  2. Or set as parameter in your synthesis script")


@app.command()
def validate(
    engine: str = typer.Argument(..., help="Path to engine SystemVerilog file"),
    license_key: str = typer.Option(..., "--key", "-k", help="License key to validate"),
):
    """Validate that an engine is properly licensed."""
    from pathlib import Path
    
    engine_path = Path(engine)
    if not engine_path.exists():
        console.print(f"[red]Engine file not found: {engine}[/red]")
        raise typer.Exit(1)
    
    # Check if engine has LICENSE_KEY parameter
    content = engine_path.read_text()
    
    if "LICENSE_KEY" not in content:
        console.print("[yellow]Warning: Engine does not have LICENSE_KEY parameter[/yellow]")
        console.print("This engine may not be properly licensed.")
        raise typer.Exit(1)
    
    # Extract expected hash from license key
    expected_hash = license_key.replace("256'h", "").replace("0x", "")
    
    console.print(f"[green]License key format valid[/green]")
    console.print(f"Key: {expected_hash[:16]}...")
    console.print("\nNote: Runtime validation requires synthesis with the license key.")


@app.command()
def sign(
    evidence_dir: str = typer.Argument(..., help="Path to evidence pack directory"),
    secret_key: str = typer.Option(..., "--key", "-k", help="Secret signing key"),
):
    """Sign an evidence pack with tamper-evident signature."""
    script_path = Path(__file__).parent.parent / "scripts" / "sign_evidence.py"
    
    if not script_path.exists():
        console.print(f"[red]Signing script not found: {script_path}[/red]")
        raise typer.Exit(1)
    
    # Run signing script
    cmd = f"python {script_path} {evidence_dir} --key {secret_key}"
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    
    if result.returncode == 0:
        console.print(f"[green]{result.stdout}[/green]")
    else:
        console.print(f"[red]{result.stderr}[/red]")
        raise typer.Exit(1)


@app.command()
def verify(
    evidence_dir: str = typer.Argument(..., help="Path to evidence pack directory"),
    secret_key: str = typer.Option(..., "--key", "-k", help="Secret signing key"),
):
    """Verify evidence pack signature."""
    script_path = Path(__file__).parent.parent / "scripts" / "sign_evidence.py"
    
    if not script_path.exists():
        console.print(f"[red]Signing script not found: {script_path}[/red]")
        raise typer.Exit(1)
    
    # Run verification
    cmd = f"python {script_path} {evidence_dir} --key {secret_key} --verify"
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    
    if result.returncode == 0:
        console.print(f"[green]{result.stdout}[/green]")
    else:
        console.print(f"[red]{result.stderr}[/red]")
        raise typer.Exit(1)


@app.command()
def verify_token(
    token: str = typer.Argument(..., help="License token to verify"),
    public_key_file: str = typer.Option(..., "--public-key", "-p", help="Path to public key PEM file"),
):
    """Verify a license token offline using a public key file."""
    from .license_crypto import load_public_key, verify_token as crypto_verify

    pk_path = Path(public_key_file)
    if not pk_path.exists():
        console.print(f"[red]Public key file not found: {public_key_file}[/red]")
        raise typer.Exit(1)

    pub = load_public_key(pk_path.read_bytes())
    try:
        payload = crypto_verify(pub, token)
    except Exception as e:
        console.print(f"[red]Verification failed: {e}[/red]")
        raise typer.Exit(1)

    console.print("[green]Token signature valid[/green]")
    console.print(f"  Engine:   {payload.get('engine', 'N/A')}")
    console.print(f"  Customer: {payload.get('customer', 'N/A')}")
    console.print(f"  Tier:     {payload.get('tier', 'N/A')}")
    console.print(f"  Issued:   {payload.get('issued_at', 'N/A')}")
    console.print(f"  Expires:  {payload.get('expires_at', 'never')}")
    console.print(f"  Key ver:  {payload.get('key_version', 'N/A')}")


if __name__ == "__main__":
    app()
