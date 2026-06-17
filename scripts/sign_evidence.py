#!/usr/bin/env python3
"""
GSAF Evidence Pack Signing Tool

Signs evidence packs with a license hash to create tamper-evident bundles.
Clients can verify the signature to ensure evidence integrity.

Usage:
    python scripts/sign_evidence.py evidence-pack/02_engine_modexp --key secret.key
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path
from datetime import datetime


def compute_evidence_hash(evidence_dir: Path) -> str:
    """Compute SHA-256 hash of all evidence files."""
    hasher = hashlib.sha256()
    
    # Sort files for deterministic ordering
    files = sorted(evidence_dir.rglob("*"))
    
    for f in files:
        if f.is_file():
            # Include relative path in hash
            rel_path = f.relative_to(evidence_dir)
            hasher.update(str(rel_path).encode())
            hasher.update(f.read_bytes())
    
    return hasher.hexdigest()


def create_manifest(evidence_dir: Path, signature: str) -> dict:
    """Create a signed manifest for the evidence pack."""
    manifest = {
        "version": "0.1.0",
        "timestamp": datetime.utcnow().isoformat(),
        "evidence_dir": str(evidence_dir.name),
        "signature": signature,
        "files": []
    }
    
    # List all files
    for f in sorted(evidence_dir.rglob("*")):
        if f.is_file():
            rel_path = f.relative_to(evidence_dir)
            manifest["files"].append({
                "path": str(rel_path),
                "size": f.stat().st_size,
                "hash": hashlib.sha256(f.read_bytes()).hexdigest()
            })
    
    return manifest


def sign_manifest(manifest: dict, secret_key: str) -> str:
    """Sign the manifest with HMAC-SHA256."""
    import hmac
    
    # Create canonical JSON
    canonical = json.dumps(manifest, sort_keys=True, separators=(',', ':'))
    
    # Compute HMAC
    signature = hmac.new(
        secret_key.encode(),
        canonical.encode(),
        hashlib.sha256
    ).hexdigest()
    
    return signature


def verify_signature(manifest: dict, secret_key: str) -> bool:
    """Verify manifest signature."""
    import hmac
    
    # Extract signature
    stored_signature = manifest.pop("signature")
    
    # Recompute
    canonical = json.dumps(manifest, sort_keys=True, separators=(',', ':'))
    computed = hmac.new(
        secret_key.encode(),
        canonical.encode(),
        hashlib.sha256
    ).hexdigest()
    
    return hmac.compare_digest(stored_signature, computed)


def main():
    parser = argparse.ArgumentParser(description="GSAF Evidence Pack Signing Tool")
    parser.add_argument("evidence_dir", help="Path to evidence pack directory")
    parser.add_argument("--key", "-k", required=True, help="Secret signing key")
    parser.add_argument("--verify", "-v", action="store_true",
                       help="Verify existing signature instead of signing")
    args = parser.parse_args()
    
    evidence_dir = Path(args.evidence_dir)
    if not evidence_dir.exists():
        print(f"Error: Evidence directory not found: {args.evidence_dir}")
        sys.exit(1)
    
    if args.verify:
        # Load and verify existing manifest
        manifest_path = evidence_dir / "MANIFEST.json"
        if not manifest_path.exists():
            print("Error: No MANIFEST.json found")
            sys.exit(1)
        
        manifest = json.loads(manifest_path.read_text())
        if verify_signature(manifest, args.key):
            print("PASS: Signature verified")
            sys.exit(0)
        else:
            print("FAIL: Signature verification failed")
            sys.exit(1)
    else:
        # Create and sign new manifest
        print(f"Signing evidence pack: {evidence_dir}")
        
        # Compute evidence hash
        evidence_hash = compute_evidence_hash(evidence_dir)
        print(f"Evidence hash: {evidence_hash[:16]}...")
        
        # Create manifest
        manifest = create_manifest(evidence_dir, "")
        
        # Sign
        signature = sign_manifest(manifest, args.key)
        manifest["signature"] = signature
        
        # Write manifest
        manifest_path = evidence_dir / "MANIFEST.json"
        manifest_path.write_text(json.dumps(manifest, indent=2))
        
        print(f"Manifest written: {manifest_path}")
        print(f"Signature: {signature[:16]}...")
        print("\nTo verify:")
        print(f"  python scripts/sign_evidence.py {evidence_dir} --key <key> --verify")


if __name__ == "__main__":
    main()
