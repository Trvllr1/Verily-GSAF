"""Test the full license flow using CLI commands + HTTP server."""
import os, sys, json, time, threading, subprocess

DB = "test_flow.db"
TOKEN_FILE = "latest.token"
if os.path.exists(DB):
    os.remove(DB)
if os.path.exists(TOKEN_FILE):
    os.remove(TOKEN_FILE)

# Start server in a thread
from gsaf_cli.license_server import app, configure
from gsaf_cli.license_models import init_first_key

configure(DB, "test-key-123")
init_first_key(DB)

import uvicorn
cfg = uvicorn.Config(app, host="127.0.0.1", port=8423, log_level="error")
server = uvicorn.Server(cfg)
t = threading.Thread(target=server.run, daemon=True)
t.start()
time.sleep(1)

BASE = "http://127.0.0.1:8423"
CLI = [sys.executable, "-m", "gsaf_cli"]

def run_cli(*args):
    result = subprocess.run(
        CLI + list(args),
        capture_output=True, text=True, cwd=os.getcwd()
    )
    return result.stdout + result.stderr, result.returncode

# ── 1. Issue a license ────────────────────────────────────────────────
print("=== 1. Issue license ===")
out, rc = run_cli(
    "license-issue",
    "--server", BASE,
    "--admin-key", "test-key-123",
    "--engine", "modexp",
    "--customer", "Acme Corp",
    "--tier", "paid",
)
print(out)
assert rc == 0, "issue failed"
assert os.path.exists(TOKEN_FILE), "token file not created"

token = open(TOKEN_FILE).read().strip()
print("Token length:", len(token))
print("PASS")

# ── 2. Validate with CLI ──────────────────────────────────────────────
print("\n=== 2. Validate with CLI ===")
out2, rc2 = run_cli(
    "license-validate",
    "--server", BASE,
    "--token", token,
)
print(out2)
assert rc2 == 0, "validate failed: " + out2
assert "valid" in out2.lower()
print("PASS")

# ── 3. Revoke with CLI ────────────────────────────────────────────────
print("\n=== 3. Revoke with CLI ===")
import urllib.request
req = urllib.request.Request(BASE + "/license/list", headers={"Authorization": "Bearer test-key-123"})
with urllib.request.urlopen(req) as resp:
    licenses = json.loads(resp.read())["licenses"]
lid = licenses[0]["id"]
print("Revoking:", lid)

out3, rc3 = run_cli(
    "license-revoke",
    "--server", BASE,
    "--admin-key", "test-key-123",
    "--license-id", lid,
)
print(out3)
assert rc3 == 0, "revoke failed"
print("PASS")

# ── 4. Validate again (should be revoked) ─────────────────────────────
print("\n=== 4. Validate revoked license ===")
out4, rc4 = run_cli(
    "license-validate",
    "--server", BASE,
    "--token", token,
)
print(out4)
assert rc4 != 0, "should have failed for revoked license"
assert "revoked" in out4.lower()
print("PASS - correctly rejected")

# ── 5. Rotate key ─────────────────────────────────────────────────────
print("\n=== 5. Rotate key ===")
out5, rc5 = run_cli(
    "license-rotate",
    "--server", BASE,
    "--admin-key", "test-key-123",
)
print(out5)
assert rc5 == 0, "rotate failed"
print("PASS")

# ── 6. Issue with new key, validate ───────────────────────────────────
print("\n=== 6. Issue + validate with new key ===")
if os.path.exists(TOKEN_FILE):
    os.remove(TOKEN_FILE)
out6, rc6 = run_cli(
    "license-issue",
    "--server", BASE,
    "--admin-key", "test-key-123",
    "--engine", "modinv",
    "--customer", "Beta Inc",
    "--tier", "enterprise",
)
print(out6)
assert rc6 == 0

token2 = open(TOKEN_FILE).read().strip()
out7, rc7 = run_cli(
    "license-validate",
    "--server", BASE,
    "--token", token2,
)
print(out7)
assert rc7 == 0, "validate with new key failed"
print("PASS")

# Shutdown
server.should_exit = True
t.join(timeout=3)
os.remove(DB)
os.remove(TOKEN_FILE)

print("\n" + "=" * 50)
print("FULL CLI FLOW: ALL TESTS PASSED")
print("=" * 50)
