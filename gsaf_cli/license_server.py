"""GSAF License Validation Server — FastAPI application."""
import os
import json
from datetime import datetime, timezone
from typing import Optional

from fastapi import FastAPI, HTTPException, Header
from pydantic import BaseModel

from .license_models import (
    init_first_key,
    issue_license,
    revoke_license,
    validate_license_token,
    list_licenses,
    list_keys,
    rotate_key,
    get_audit_log,
    get_current_key,
)

app = FastAPI(
    title="GSAF License Server",
    version="0.2.0",
    description="License validation, key rotation, and revocation for GSAF cryptographic IP cores.",
)

DB_PATH = os.environ.get("GSAF_LICENSE_DB", "licenses.db")
ADMIN_KEY = os.environ.get("GSAF_ADMIN_KEY", "")


def configure(db_path: str, admin_key: str):
    """Set database path and admin key at startup."""
    global DB_PATH, ADMIN_KEY
    DB_PATH = db_path
    ADMIN_KEY = admin_key


def _check_admin(authorization: str = Header(None)):
    if not ADMIN_KEY:
        return
    if not authorization or authorization != f"Bearer {ADMIN_KEY}":
        raise HTTPException(status_code=403, detail="Invalid or missing admin API key")


class IssueRequest(BaseModel):
    engine: str
    customer: str
    tier: str = "paid"
    expires_at: Optional[str] = None


class ValidateRequest(BaseModel):
    token: str


class RevokeRequest(BaseModel):
    license_id: str


@app.on_event("startup")
def startup():
    init_first_key(DB_PATH)


@app.get("/license/status")
def status():
    try:
        version, _, _ = get_current_key(DB_PATH)
    except Exception:
        version = None
    return {"status": "ok", "current_key_version": version}


@app.get("/license/public-key")
def public_key():
    try:
        from .license_crypto import serialize_public_key
        _, _, pub = get_current_key(DB_PATH)
        pem = serialize_public_key(pub).decode()
        return {"public_key": pem}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/license/issue")
def issue(req: IssueRequest, authorization: str = Header(None)):
    _check_admin(authorization)
    result = issue_license(
        DB_PATH,
        engine=req.engine,
        customer=req.customer,
        tier=req.tier,
        expires_at=req.expires_at,
    )
    return result


@app.post("/license/validate")
def validate(req: ValidateRequest):
    result = validate_license_token(DB_PATH, req.token)
    if result["status"] == "valid":
        return result
    status_code = {
        "revoked": 410,
        "expired": 410,
        "invalid_signature": 401,
        "unknown_key": 503,
        "not_found": 404,
    }.get(result["status"], 400)
    raise HTTPException(status_code=status_code, detail=result)


@app.post("/license/revoke")
def revoke(req: RevokeRequest, authorization: str = Header(None)):
    _check_admin(authorization)
    success = revoke_license(DB_PATH, req.license_id)
    if not success:
        raise HTTPException(status_code=404, detail="License not found or already revoked")
    return {"status": "revoked", "license_id": req.license_id}


@app.get("/license/list")
def licenses(authorization: str = Header(None)):
    _check_admin(authorization)
    return {"licenses": list_licenses(DB_PATH, include_revoked=True)}


@app.post("/keys/rotate")
def rotate(authorization: str = Header(None)):
    _check_admin(authorization)
    new_version = rotate_key(DB_PATH)
    return {"status": "rotated", "new_key_version": new_version}


@app.get("/keys")
def keys(authorization: str = Header(None)):
    _check_admin(authorization)
    return {"keys": list_keys(DB_PATH)}


@app.get("/audit")
def audit(limit: int = 50, authorization: str = Header(None)):
    _check_admin(authorization)
    return {"entries": get_audit_log(DB_PATH, limit)}
