"""Ed25519 key generation, signing, and verification for GSAF licenses."""
import base64
import json
from datetime import datetime, timezone
from pathlib import Path

from cryptography.hazmat.primitives.asymmetric.ed25519 import (
    Ed25519PrivateKey,
    Ed25519PublicKey,
)
from cryptography.hazmat.primitives import serialization


def generate_keypair():
    """Generate a new Ed25519 key pair. Returns (private_key, public_key)."""
    private_key = Ed25519PrivateKey.generate()
    public_key = private_key.public_key()
    return private_key, public_key


def serialize_private_key(private_key, password=None):
    """Serialize private key to PEM bytes."""
    encryption = (
        serialization.BestAvailableEncryption(password.encode())
        if password
        else serialization.NoEncryption()
    )
    return private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=encryption,
    )


def serialize_public_key(public_key):
    """Serialize public key to PEM bytes."""
    return public_key.public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    )


def load_private_key(pem_bytes, password=None):
    """Load private key from PEM bytes."""
    pwd = password.encode() if password else None
    return serialization.load_pem_private_key(pem_bytes, password=pwd)


def load_public_key(pem_bytes):
    """Load public key from PEM bytes."""
    return serialization.load_pem_public_key(pem_bytes)


def sign_token(private_key, payload: dict) -> str:
    """Sign a license payload and return a base64 token.

    Token format: base64(payload_json).base64(signature)
    """
    payload_bytes = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()
    signature = private_key.sign(payload_bytes)
    payload_b64 = base64.urlsafe_b64encode(payload_bytes).decode()
    sig_b64 = base64.urlsafe_b64encode(signature).decode()
    return f"{payload_b64}.{sig_b64}"


def verify_token(public_key, token: str) -> dict:
    """Verify a license token and return the payload dict.

    Raises ValueError if signature is invalid.
    """
    try:
        payload_b64, sig_b64 = token.split(".", 1)
        payload_bytes = base64.urlsafe_b64decode(payload_b64)
        signature = base64.urlsafe_b64decode(sig_b64)
    except Exception:
        raise ValueError("Invalid token format")

    public_key.verify(signature, payload_bytes)
    return json.loads(payload_bytes)


def create_license_payload(
    engine: str,
    customer: str,
    tier: str = "paid",
    key_version: int = 1,
    expires_at: str | None = None,
) -> dict:
    """Build a license payload dict with standard fields."""
    now = datetime.now(timezone.utc).isoformat()
    return {
        "engine": engine,
        "customer": customer,
        "tier": tier,
        "key_version": key_version,
        "issued_at": now,
        "expires_at": expires_at,
    }
