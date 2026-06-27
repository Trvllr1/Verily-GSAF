"""GSAF License Server — full test script.
Run: python test_license_server.py
"""
import os, sys, json, time, threading, urllib.request

DB = "test_server.db"
if os.path.exists(DB):
    os.remove(DB)

# ── 1. Test crypto layer ──────────────────────────────────────────────
print("=== 1. Crypto layer (Ed25519) ===")
from gsaf_cli.license_crypto import generate_keypair, sign_token, verify_token, create_license_payload

priv, pub = generate_keypair()
payload = create_license_payload(engine="modexp", customer="Test", tier="paid", key_version=1)
token = sign_token(priv, payload)
verified = verify_token(pub, token)
assert verified["engine"] == "modexp", "engine mismatch"
print("  PASS — sign + verify works")

# Bad signature
bad_payload = create_license_payload(engine="modinv", customer="X", tier="free", key_version=1)
bad_token = sign_token(priv, bad_payload)
try:
    # tamper with token
    parts = bad_token.split(".")
    tampered = parts[0] + ".AAAA" + parts[1][4:]
    verify_token(pub, tampered)
    print("  FAIL — should have rejected bad signature")
    sys.exit(1)
except Exception:
    print("  PASS — bad signature rejected")

# ── 2. Test models layer (SQLite) ─────────────────────────────────────
print("\n=== 2. Models layer (SQLite) ===")
from gsaf_cli.license_models import (
    init_first_key, issue_license, validate_license_token,
    revoke_license, rotate_key, list_keys, list_licenses, get_audit_log
)

init_first_key(DB)
keys = list_keys(DB)
assert len(keys) == 1, "expected 1 key"
assert keys[0]["is_current"] == 1, "key not current"
print("  PASS — init creates first key (v1)")

lic = issue_license(DB, "modexp", "Acme Corp", "paid")
assert lic["key_version"] == 1
print("  PASS — issue license with key v1")

r = validate_license_token(DB, lic["token"])
assert r["status"] == "valid", "expected valid, got " + r["status"]
print("  PASS — validate returns valid")

revoke_license(DB, lic["license_id"])
r2 = validate_license_token(DB, lic["token"])
assert r2["status"] == "revoked", "expected revoked"
print("  PASS — revoke works")

nv = rotate_key(DB)
assert nv == 2, "expected version 2"
keys2 = list_keys(DB)
assert len(keys2) == 2
print("  PASS — key rotation creates v2")

lic2 = issue_license(DB, "modinv", "Beta Inc", "enterprise")
assert lic2["key_version"] == 2
r3 = validate_license_token(DB, lic2["token"])
assert r3["status"] == "valid"
print("  PASS — license issued with key v2 validates")

all_lic = list_licenses(DB, include_revoked=True)
active = list_licenses(DB, include_revoked=False)
assert len(all_lic) == 2
assert len(active) == 1
print("  PASS — list filters revoked correctly")

log = get_audit_log(DB)
assert len(log) >= 5
print("  PASS — audit log has", len(log), "entries")

os.remove(DB)
print("  PASS — all model tests passed")

# ── 3. Test HTTP server ───────────────────────────────────────────────
print("\n=== 3. HTTP server ===")
from gsaf_cli.license_server import app, configure

ADMIN = "test-admin-123"
configure(DB, ADMIN)

# Initialize DB for server
from gsaf_cli.license_models import init_first_key
init_first_key(DB)

# Start uvicorn in a thread
import uvicorn
server_config = uvicorn.Config(app, host="127.0.0.1", port=8421, log_level="error")
server = uvicorn.Server(server_config)
thread = threading.Thread(target=server.run, daemon=True)
thread.start()
time.sleep(1)  # wait for startup

BASE = "http://127.0.0.1:8421"

def api_get(path, auth=None):
    headers = {}
    if auth:
        headers["Authorization"] = f"Bearer {auth}"
    req = urllib.request.Request(BASE + path, headers=headers)
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read()), resp.status

def api_post(path, data, auth=None):
    headers = {"Content-Type": "application/json"}
    if auth:
        headers["Authorization"] = f"Bearer {auth}"
    req = urllib.request.Request(BASE + path, data=json.dumps(data).encode(), headers=headers)
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read()), resp.status
    except urllib.error.HTTPError as e:
        return json.loads(e.read()), e.code

# Status
resp, code = api_get("/license/status")
assert code == 200 and resp["status"] == "ok"
print("  PASS — GET /license/status")

# Public key
resp, code = api_get("/license/public-key")
assert code == 200 and "public_key" in resp
print("  PASS — GET /license/public-key")

# Issue (requires auth)
resp, code = api_post("/license/issue", {"engine": "modexp", "customer": "HTTP Corp", "tier": "paid"}, auth=ADMIN)
assert code == 200 and "token" in resp
token = resp["token"]
lid = resp["license_id"]
print("  PASS — POST /license/issue (license:", lid[:8] + "...")

# Issue without auth (should fail)
resp, code = api_post("/license/issue", {"engine": "x", "customer": "y"})
assert code == 403
print("  PASS — POST /license/issue without auth returns 403")

# Validate
resp, code = api_post("/license/validate", {"token": token})
assert code == 200 and resp["status"] == "valid"
print("  PASS — POST /license/validate returns valid")

# Revoke
resp, code = api_post("/license/revoke", {"license_id": lid}, auth=ADMIN)
assert code == 200 and resp["status"] == "revoked"
print("  PASS — POST /license/revoke")

# Validate revoked
resp, code = api_post("/license/validate", {"token": token})
assert code == 410
print("  PASS — POST /license/validate returns 410 after revoke")

# Key rotation
resp, code = api_post("/keys/rotate", {}, auth=ADMIN)
assert code == 200 and resp["new_key_version"] == 2
print("  PASS — POST /keys/rotate -> v2")

# List keys
resp, code = api_get("/keys", auth=ADMIN)
assert code == 200 and len(resp["keys"]) == 2
print("  PASS — GET /keys (count:", len(resp["keys"]), ")")

# Audit log
resp, code = api_get("/audit", auth=ADMIN)
assert code == 200 and len(resp["entries"]) > 0
print("  PASS — GET /audit (entries:", len(resp["entries"]), ")")

# List licenses
resp, code = api_get("/license/list", auth=ADMIN)
assert code == 200
print("  PASS — GET /license/list")

# Shutdown
server.should_exit = True
thread.join(timeout=3)
os.remove(DB)

print("\n" + "=" * 50)
print("ALL 20 TESTS PASSED")
print("=" * 50)
