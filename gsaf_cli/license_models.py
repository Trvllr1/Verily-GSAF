"""SQLite storage for GSAF licenses, keys, and audit log."""
import json
import sqlite3
import uuid
from datetime import datetime, timezone
from pathlib import Path

from .license_crypto import (
    generate_keypair,
    serialize_private_key,
    serialize_public_key,
    load_private_key,
    load_public_key,
    sign_token,
    create_license_payload,
)

SCHEMA = """
CREATE TABLE IF NOT EXISTS keys (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    version INTEGER UNIQUE NOT NULL,
    public_key_pem TEXT NOT NULL,
    private_key_pem TEXT NOT NULL,
    created_at TEXT NOT NULL,
    is_current INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS licenses (
    id TEXT PRIMARY KEY,
    engine TEXT NOT NULL,
    customer TEXT NOT NULL,
    tier TEXT DEFAULT 'paid',
    issued_at TEXT NOT NULL,
    expires_at TEXT,
    revoked_at TEXT,
    key_version INTEGER NOT NULL,
    token TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS audit_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    action TEXT NOT NULL,
    license_id TEXT,
    details TEXT,
    timestamp TEXT NOT NULL
);
"""


def get_db(db_path: str) -> sqlite3.Connection:
    """Open database connection and ensure schema exists."""
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    conn.executescript(SCHEMA)
    return conn


def _now():
    return datetime.now(timezone.utc).isoformat()


def init_first_key(db_path: str):
    """Generate the initial key pair if none exists."""
    conn = get_db(db_path)
    row = conn.execute("SELECT COUNT(*) as cnt FROM keys").fetchone()
    if row["cnt"] == 0:
        private_key, public_key = generate_keypair()
        priv_pem = serialize_private_key(private_key).decode()
        pub_pem = serialize_public_key(public_key).decode()
        conn.execute(
            "INSERT INTO keys (version, public_key_pem, private_key_pem, created_at, is_current) "
            "VALUES (1, ?, ?, ?, 1)",
            (pub_pem, priv_pem, _now()),
        )
        conn.commit()
    conn.close()


def rotate_key(db_path: str) -> int:
    """Generate a new key pair, mark as current, return new version number."""
    conn = get_db(db_path)
    conn.execute("UPDATE keys SET is_current = 0")
    row = conn.execute("SELECT MAX(version) as maxv FROM keys").fetchone()
    new_version = (row["maxv"] or 0) + 1

    private_key, public_key = generate_keypair()
    priv_pem = serialize_private_key(private_key).decode()
    pub_pem = serialize_public_key(public_key).decode()
    conn.execute(
        "INSERT INTO keys (version, public_key_pem, private_key_pem, created_at, is_current) "
        "VALUES (?, ?, ?, ?, 1)",
        (new_version, pub_pem, priv_pem, _now()),
    )
    conn.commit()
    conn.close()
    return new_version


def get_current_key(db_path: str):
    """Return (version, private_key_obj, public_key_obj) for current key."""
    conn = get_db(db_path)
    row = conn.execute("SELECT * FROM keys WHERE is_current = 1").fetchone()
    conn.close()
    if not row:
        raise RuntimeError("No current key found. Run init or rotate first.")
    priv = load_private_key(row["private_key_pem"].encode())
    pub = load_public_key(row["public_key_pem"].encode())
    return row["version"], priv, pub


def get_key_by_version(db_path: str, version: int):
    """Return (private_key_obj, public_key_obj) for a specific key version."""
    conn = get_db(db_path)
    row = conn.execute("SELECT * FROM keys WHERE version = ?", (version,)).fetchone()
    conn.close()
    if not row:
        raise KeyError(f"Key version {version} not found")
    priv = load_private_key(row["private_key_pem"].encode())
    pub = load_public_key(row["public_key_pem"].encode())
    return priv, pub


def list_keys(db_path: str) -> list[dict]:
    """List all key versions."""
    conn = get_db(db_path)
    rows = conn.execute(
        "SELECT id, version, created_at, is_current FROM keys ORDER BY version"
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]


def issue_license(
    db_path: str,
    engine: str,
    customer: str,
    tier: str = "paid",
    expires_at: str | None = None,
) -> dict:
    """Issue a new license: build payload, sign it, store in DB. Returns license dict."""
    conn = get_db(db_path)
    version, priv, pub = get_current_key(db_path)

    license_id = str(uuid.uuid4())
    payload = create_license_payload(
        engine=engine,
        customer=customer,
        tier=tier,
        key_version=version,
        expires_at=expires_at,
    )
    token = sign_token(priv, payload)

    conn.execute(
        "INSERT INTO licenses (id, engine, customer, tier, issued_at, expires_at, revoked_at, key_version, token) "
        "VALUES (?, ?, ?, ?, ?, ?, NULL, ?, ?)",
        (license_id, engine, customer, tier, payload["issued_at"], expires_at, version, token),
    )
    conn.execute(
        "INSERT INTO audit_log (action, license_id, details, timestamp) VALUES (?, ?, ?, ?)",
        ("issue", license_id, json.dumps({"engine": engine, "customer": customer, "tier": tier}), _now()),
    )
    conn.commit()
    conn.close()
    return {"license_id": license_id, "token": token, "key_version": version}


def revoke_license(db_path: str, license_id: str) -> bool:
    """Revoke a license by ID. Returns True if found and revoked."""
    conn = get_db(db_path)
    row = conn.execute("SELECT * FROM licenses WHERE id = ?", (license_id,)).fetchone()
    if not row:
        conn.close()
        return False
    if row["revoked_at"]:
        conn.close()
        return False

    conn.execute("UPDATE licenses SET revoked_at = ? WHERE id = ?", (_now(), license_id))
    conn.execute(
        "INSERT INTO audit_log (action, license_id, details, timestamp) VALUES (?, ?, ?, ?)",
        ("revoke", license_id, None, _now()),
    )
    conn.commit()
    conn.close()
    return True


def validate_license_token(db_path: str, token: str) -> dict:
    """Validate a license token. Returns status dict.

    Possible statuses: valid, expired, revoked, invalid_signature, unknown_key, not_found
    """
    from .license_crypto import verify_token

    conn = get_db(db_path)

    row = conn.execute("SELECT * FROM licenses WHERE token = ?", (token,)).fetchone()
    if not row:
        conn.close()
        return {"status": "not_found", "detail": "No license found for this token"}

    if row["revoked_at"]:
        conn.close()
        return {"status": "revoked", "detail": f"Revoked at {row['revoked_at']}", "license_id": row["id"]}

    if row["expires_at"]:
        from datetime import datetime, timezone
        try:
            exp = datetime.fromisoformat(row["expires_at"])
            if datetime.now(timezone.utc) > exp:
                conn.close()
                return {"status": "expired", "detail": f"Expired at {row['expires_at']}", "license_id": row["id"]}
        except Exception:
            pass

    try:
        _, pub = get_key_by_version(db_path, row["key_version"])
    except KeyError:
        conn.close()
        return {"status": "unknown_key", "detail": f"Key version {row['key_version']} no longer available"}

    try:
        payload = verify_token(pub, token)
    except Exception:
        conn.close()
        return {"status": "invalid_signature", "detail": "Token signature verification failed"}

    conn.execute(
        "INSERT INTO audit_log (action, license_id, details, timestamp) VALUES (?, ?, ?, ?)",
        ("validate", row["id"], json.dumps(payload), _now()),
    )
    conn.commit()
    conn.close()
    return {"status": "valid", "license_id": row["id"], "payload": payload}


def list_licenses(db_path: str, include_revoked: bool = False) -> list[dict]:
    """List all licenses."""
    conn = get_db(db_path)
    if include_revoked:
        rows = conn.execute("SELECT * FROM licenses ORDER BY issued_at DESC").fetchall()
    else:
        rows = conn.execute("SELECT * FROM licenses WHERE revoked_at IS NULL ORDER BY issued_at DESC").fetchall()
    conn.close()
    return [dict(r) for r in rows]


def get_audit_log(db_path: str, limit: int = 50) -> list[dict]:
    """Get recent audit log entries."""
    conn = get_db(db_path)
    rows = conn.execute(
        "SELECT * FROM audit_log ORDER BY id DESC LIMIT ?", (limit,)
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]
