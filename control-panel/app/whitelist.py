import os
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel
from typing import Optional
from app.auth import get_current_user
from app.squid_service import reconfigure_squid
from app.audit import log_control_operation

router = APIRouter(prefix="/api/whitelist", tags=["whitelist"])

DATA_DIR = os.getenv("DATA_DIR", "/app/data")
WHITELIST_FILE = os.path.join(DATA_DIR, "whitelist.txt")

class DomainItem(BaseModel):
    domain: str
    enabled: bool = True

class AddDomainRequest(BaseModel):
    domain: str

class ToggleDomainRequest(BaseModel):
    enabled: bool

def parse_whitelist_file() -> tuple[list[dict], list[str]]:
    items = []
    header_lines = []
    if not os.path.exists(WHITELIST_FILE):
        return items, header_lines

    try:
        with open(WHITELIST_FILE, "r", encoding="utf-8") as f:
            lines = f.readlines()

        for line in lines:
            stripped = line.strip()
            if not stripped:
                continue
            if stripped.startswith("# ALL BLOCKED"):
                continue

            # Check if commented domain e.g. # .googleapis.com or # github.com
            if stripped.startswith("#"):
                comment_content = stripped[1:].strip()
                if "." in comment_content and not comment_content.startswith("="):
                    items.append({"domain": comment_content, "enabled": False})
                else:
                    header_lines.append(line if line.endswith("\n") else line + "\n")
            else:
                items.append({"domain": stripped, "enabled": True})
    except Exception as e:
        print(f"Error parsing whitelist file: {e}")

    return items, header_lines

def write_whitelist_items(items: list[dict], header_lines: list[str] = None):
    lines = list(header_lines) if header_lines else []
    for item in items:
        dom = item["domain"].strip()
        if item["enabled"]:
            lines.append(f"{dom}\n")
        else:
            lines.append(f"# {dom}\n")
            
    with open(WHITELIST_FILE, "w", encoding="utf-8") as f:
        f.writelines(lines)

@router.get("", dependencies=[Depends(get_current_user)])
def get_whitelist():
    items, _ = parse_whitelist_file()
    return {"domains": items, "count": len(items)}

@router.post("", dependencies=[Depends(get_current_user)])
def add_domain(body: AddDomainRequest, request: Request):
    client_ip = request.client.host if request.client else "unknown"
    domain = body.domain.strip()
    if not domain:
        raise HTTPException(status_code=400, detail="ドメイン名を入力してください。")

    items, headers = parse_whitelist_file()
    for item in items:
        if item["domain"].lower() == domain.lower():
            raise HTTPException(status_code=400, detail=f"ドメイン '{domain}' は既に登録されています。")

    items.append({"domain": domain, "enabled": True})
    write_whitelist_items(items, headers)

    reconfig_ok, reconfig_msg = reconfigure_squid()

    log_control_operation(
        action="whitelist_add",
        details=f"ドメイン追加: {domain} ({reconfig_msg})",
        client_ip=client_ip
    )

    return {"status": "ok", "message": f"ドメイン '{domain}' を追加しました。", "squid_reloaded": reconfig_ok}

@router.delete("/{domain:path}", dependencies=[Depends(get_current_user)])
def delete_domain(domain: str, request: Request):
    client_ip = request.client.host if request.client else "unknown"
    domain = domain.strip()

    items, headers = parse_whitelist_file()
    new_items = [item for item in items if item["domain"].lower() != domain.lower()]

    if len(new_items) == len(items):
        raise HTTPException(status_code=404, detail=f"ドメイン '{domain}' が見つかりません。")

    write_whitelist_items(new_items, headers)
    reconfig_ok, reconfig_msg = reconfigure_squid()

    log_control_operation(
        action="whitelist_delete",
        details=f"ドメイン削除: {domain} ({reconfig_msg})",
        client_ip=client_ip
    )

    return {"status": "ok", "message": f"ドメイン '{domain}' を削除しました。", "squid_reloaded": reconfig_ok}

@router.patch("/{domain:path}", dependencies=[Depends(get_current_user)])
def toggle_domain(domain: str, body: ToggleDomainRequest, request: Request):
    client_ip = request.client.host if request.client else "unknown"
    domain = domain.strip()

    items, headers = parse_whitelist_file()
    found = False
    for item in items:
        if item["domain"].lower() == domain.lower():
            item["enabled"] = body.enabled
            found = True
            break

    if not found:
        raise HTTPException(status_code=404, detail=f"ドメイン '{domain}' が見つかりません。")

    write_whitelist_items(items, headers)
    reconfig_ok, reconfig_msg = reconfigure_squid()

    state_str = "有効化" if body.enabled else "無効化"
    log_control_operation(
        action="whitelist_toggle",
        details=f"ドメイン{state_str}: {domain} ({reconfig_msg})",
        client_ip=client_ip
    )

    return {"status": "ok", "message": f"ドメイン '{domain}' を{state_str}しました。", "squid_reloaded": reconfig_ok}

@router.post("/reload", dependencies=[Depends(get_current_user)])
def reload_squid_config(request: Request):
    client_ip = request.client.host if request.client else "unknown"
    reconfig_ok, reconfig_msg = reconfigure_squid()

    log_control_operation(
        action="whitelist_reload",
        details=f"Squid 手動設定再読み込み: {reconfig_msg}",
        client_ip=client_ip
    )

    return {"status": "ok", "message": reconfig_msg, "squid_reloaded": reconfig_ok}
