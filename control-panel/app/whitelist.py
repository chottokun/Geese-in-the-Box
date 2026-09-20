import os
import re

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field

from app.audit import log_control_operation
from app.auth import get_current_user
from app.squid_service import reconfigure_squid
from app.temp_whitelist import (
    get_temp_domains_info,
    register_temp_domain,
    remove_temp_domain,
)

DOMAIN_REGEX = re.compile(r"^[a-zA-Z0-9\.\_\-\:\*]+$")

def validate_domain_format(domain: str):
    if not domain or not DOMAIN_REGEX.match(domain) or "\n" in domain or "\r" in domain:
        raise HTTPException(
            status_code=400,
            detail="invalid_domain_format"
        )

router = APIRouter(prefix="/api/whitelist", tags=["whitelist"])

DATA_DIR = os.getenv("DATA_DIR", "/app/data")
WHITELIST_FILE = os.path.join(DATA_DIR, "whitelist.txt")

class DomainItem(BaseModel):
    domain: str
    enabled: bool = True

class AddDomainRequest(BaseModel):
    domain: str

class AddTempDomainRequest(BaseModel):
    domain: str
    duration_minutes: int = Field(15, ge=1, le=1440) # 1分〜24時間

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

def write_whitelist_items(items: list[dict], header_lines: list[str] | None = None):
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
    temp_info_map = get_temp_domains_info()

    for item in items:
        dom_key = item["domain"].lower()
        if dom_key in temp_info_map:
            t_info = temp_info_map[dom_key]
            item["is_temporary"] = True
            item["expires_at"] = t_info["expires_at"]
            item["remaining_seconds"] = t_info["remaining_seconds"]
            item["duration_minutes"] = t_info["duration_minutes"]
        else:
            item["is_temporary"] = False
            item["expires_at"] = None
            item["remaining_seconds"] = None
            item["duration_minutes"] = None

    return {"domains": items, "count": len(items)}

@router.post("", dependencies=[Depends(get_current_user)])
def add_domain(body: AddDomainRequest, request: Request):
    client_ip = request.client.host if request.client else "unknown"
    domain = body.domain.strip()
    validate_domain_format(domain)

    items, headers = parse_whitelist_file()
    for item in items:
        if item["domain"].lower() == domain.lower():
            raise HTTPException(status_code=400, detail=f"domain_exists:{domain}")

    items.append({"domain": domain, "enabled": True})
    write_whitelist_items(items, headers)

    reconfig_ok, reconfig_msg = reconfigure_squid()

    log_control_operation(
        action="whitelist_add",
        details=f"ドメイン恒久追加: {domain} ({reconfig_msg})",
        client_ip=client_ip
    )

    return {
        "status": "ok",
        "domain": domain,
        "message": "domain_added",
        "message_ja": f"ドメイン '{domain}' を追加しました。",
        "message_en": f"Domain '{domain}' added.",
        "squid_reloaded": reconfig_ok
    }

@router.post("/temporary", dependencies=[Depends(get_current_user)])
def add_temporary_domain(body: AddTempDomainRequest, request: Request):
    client_ip = request.client.host if request.client else "unknown"
    domain = body.domain.strip()
    duration = body.duration_minutes
    validate_domain_format(domain)

    items, headers = parse_whitelist_file()
    existing_item = next((item for item in items if item["domain"].lower() == domain.lower()), None)

    if existing_item:
        # すでに無効状態で存在している場合は有効化
        if not existing_item["enabled"]:
            existing_item["enabled"] = True
            write_whitelist_items(items, headers)
    else:
        items.append({"domain": domain, "enabled": True})
        write_whitelist_items(items, headers)

    temp_record = register_temp_domain(domain, duration, client_ip)
    reconfig_ok, reconfig_msg = reconfigure_squid()

    log_control_operation(
        action="whitelist_temporary_add",
        details=f"ドメイン一時許可 ({duration}分間): {domain} ({reconfig_msg})",
        client_ip=client_ip
    )

    return {
        "status": "ok",
        "domain": domain,
        "duration_minutes": duration,
        "message": "temp_domain_added",
        "message_ja": f"ドメイン '{domain}' を {duration} 分間一時許可しました。",
        "message_en": f"Temporarily whitelisted '{domain}' for {duration} minutes.",
        "squid_reloaded": reconfig_ok,
        "temporary_info": temp_record
    }

@router.delete("/{domain:path}", dependencies=[Depends(get_current_user)])
def delete_domain(domain: str, request: Request):
    client_ip = request.client.host if request.client else "unknown"
    domain = domain.strip()

    items, headers = parse_whitelist_file()
    new_items = [item for item in items if item["domain"].lower() != domain.lower()]

    if len(new_items) == len(items):
        raise HTTPException(status_code=404, detail=f"domain_not_found:{domain}")

    write_whitelist_items(new_items, headers)
    remove_temp_domain(domain)
    reconfig_ok, reconfig_msg = reconfigure_squid()

    log_control_operation(
        action="whitelist_delete",
        details=f"ドメイン削除: {domain} ({reconfig_msg})",
        client_ip=client_ip
    )

    return {
        "status": "ok",
        "domain": domain,
        "message": "domain_deleted",
        "message_ja": f"ドメイン '{domain}' を削除しました。",
        "message_en": f"Domain '{domain}' deleted.",
        "squid_reloaded": reconfig_ok
    }

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
        raise HTTPException(status_code=404, detail=f"domain_not_found:{domain}")

    write_whitelist_items(items, headers)
    reconfig_ok, reconfig_msg = reconfigure_squid()

    state_str = "有効化" if body.enabled else "無効化"
    log_control_operation(
        action="whitelist_toggle",
        details=f"ドメイン{state_str}: {domain} ({reconfig_msg})",
        client_ip=client_ip
    )

    msg_key = "domain_enabled" if body.enabled else "domain_disabled"
    msg_ja = f"ドメイン '{domain}' を有効化しました。" if body.enabled else f"ドメイン '{domain}' を無効化しました。"
    msg_en = f"Domain '{domain}' enabled." if body.enabled else f"Domain '{domain}' disabled."

    return {
        "status": "ok",
        "domain": domain,
        "enabled": body.enabled,
        "message": msg_key,
        "message_ja": msg_ja,
        "message_en": msg_en,
        "squid_reloaded": reconfig_ok
    }

@router.post("/reload", dependencies=[Depends(get_current_user)])
def reload_squid_config(request: Request):
    client_ip = request.client.host if request.client else "unknown"
    reconfig_ok, reconfig_msg = reconfigure_squid()

    log_control_operation(
        action="whitelist_reload",
        details=f"Squid 手動設定再読み込み: {reconfig_msg}",
        client_ip=client_ip
    )

    msg_ja = "Squid 設定を再読み込みしました。" if reconfig_ok else "Squid 設定の再読み込みに失敗しました。"
    msg_en = "Squid configuration reloaded successfully." if reconfig_ok else "Failed to reload Squid configuration."

    return {
        "status": "ok" if reconfig_ok else "error",
        "message": reconfig_msg,
        "message_ja": msg_ja,
        "message_en": msg_en,
        "squid_reloaded": reconfig_ok
    }
