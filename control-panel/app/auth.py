import os
import secrets
import time
from fastapi import APIRouter, HTTPException, Depends, Request, Response, Cookie
from pydantic import BaseModel
from typing import Optional

router = APIRouter(prefix="/api/auth", tags=["auth"])

CONTROL_PANEL_PASSWORD = os.getenv("CONTROL_PANEL_PASSWORD", "").strip()
DISABLE_AUTH_ENV = os.getenv("DISABLE_AUTH", "false").lower() in ("true", "1", "yes")

# If password is empty, disable auth by default for local development
IS_AUTH_ENABLED = bool(CONTROL_PANEL_PASSWORD) and not DISABLE_AUTH_ENV

# In-memory session store: token -> expiry timestamp
SESSION_TOKENS: dict[str, float] = {}
SESSION_DURATION_SECONDS = 86400  # 24 hours

class LoginRequest(BaseModel):
    password: str

class AuthStatusResponse(BaseModel):
    auth_enabled: bool
    authenticated: bool

def is_valid_token(token: Optional[str]) -> bool:
    if not IS_AUTH_ENABLED:
        return True
    if not token:
        return False
    expiry = SESSION_TOKENS.get(token)
    if not expiry:
        return False
    if time.time() > expiry:
        del SESSION_TOKENS[token]
        return False
    return True

def get_current_user(
    request: Request,
    cp_session: Optional[str] = Cookie(None)
):
    if not IS_AUTH_ENABLED:
        return True

    # Check Bearer token in Header
    auth_header = request.headers.get("Authorization")
    token = None
    if auth_header and auth_header.startswith("Bearer "):
        token = auth_header.split(" ", 1)[1]
    elif cp_session:
        token = cp_session

    if not is_valid_token(token):
        raise HTTPException(status_code=401, detail="認証が必要です。ログインしてください。")
    return True

@router.get("/status", response_model=AuthStatusResponse)
def check_auth_status(request: Request, cp_session: Optional[str] = Cookie(None)):
    auth_header = request.headers.get("Authorization")
    token = None
    if auth_header and auth_header.startswith("Bearer "):
        token = auth_header.split(" ", 1)[1]
    elif cp_session:
        token = cp_session

    authenticated = is_valid_token(token)
    return AuthStatusResponse(
        auth_enabled=IS_AUTH_ENABLED,
        authenticated=authenticated
    )

@router.post("/login")
def login(body: LoginRequest, response: Response):
    if not IS_AUTH_ENABLED:
        return {"status": "ok", "message": "認証は無効化されています。"}

    if body.password != CONTROL_PANEL_PASSWORD:
        raise HTTPException(status_code=401, detail="パスワードが正しくありません。")

    token = secrets.token_hex(32)
    SESSION_TOKENS[token] = time.time() + SESSION_DURATION_SECONDS

    # Set HttpOnly cookie and return token in body
    response.set_cookie(
        key="cp_session",
        value=token,
        httponly=True,
        samesite="lax",
        max_age=SESSION_DURATION_SECONDS,
        path="/"
    )
    return {"status": "ok", "token": token, "message": "ログインしました。"}

@router.post("/logout")
def logout(response: Response, request: Request, cp_session: Optional[str] = Cookie(None)):
    auth_header = request.headers.get("Authorization")
    token = None
    if auth_header and auth_header.startswith("Bearer "):
        token = auth_header.split(" ", 1)[1]
    elif cp_session:
        token = cp_session

    if token and token in SESSION_TOKENS:
        del SESSION_TOKENS[token]

    response.delete_cookie("cp_session", path="/")
    return {"status": "ok", "message": "ログアウトしました。"}
