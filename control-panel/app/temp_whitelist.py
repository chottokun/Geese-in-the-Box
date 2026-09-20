import asyncio
import json
import os
from datetime import datetime, timedelta, timezone

from app.audit import log_control_operation
from app.squid_service import reconfigure_squid

DATA_DIR = os.getenv("DATA_DIR", "/app/data")
TEMP_WHITELIST_FILE = os.path.join(DATA_DIR, ".temp_whitelist.json")
WHITELIST_FILE = os.path.join(DATA_DIR, "whitelist.txt")

JST = timezone(timedelta(hours=9))

def _load_temp_data() -> dict[str, dict]:
    if not os.path.exists(TEMP_WHITELIST_FILE):
        return {}
    try:
        with open(TEMP_WHITELIST_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        print(f"Failed to load temp whitelist file: {e}")
        return {}

def _save_temp_data(data: dict[str, dict]):
    try:
        os.makedirs(os.path.dirname(TEMP_WHITELIST_FILE), exist_ok=True)
        with open(TEMP_WHITELIST_FILE, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
    except Exception as e:
        print(f"Failed to save temp whitelist file: {e}")

def get_temp_domains_info() -> dict[str, dict]:
    """現在の一時許可ドメイン情報（残り時間付き）を返却"""
    now = datetime.now(timezone.utc)
    data = _load_temp_data()
    result = {}
    for domain, info in data.items():
        expires_at_iso = info.get("expires_at")
        if not expires_at_iso:
            continue
        try:
            expires_at = datetime.fromisoformat(expires_at_iso)
            remaining_seconds = max(0, int((expires_at - now).total_seconds()))
            result[domain.lower()] = {
                "expires_at": expires_at_iso,
                "duration_minutes": info.get("duration_minutes", 0),
                "remaining_seconds": remaining_seconds,
                "is_expired": remaining_seconds <= 0
            }
        except Exception:
            continue
    return result

def register_temp_domain(domain: str, duration_minutes: int, client_ip: str = "unknown") -> dict:
    """ドメインを一時許可として登録"""
    now = datetime.now(timezone.utc)
    expires_at = now + timedelta(minutes=duration_minutes)

    data = _load_temp_data()
    dom_key = domain.strip().lower()
    data[dom_key] = {
        "domain": domain.strip(),
        "created_at": now.isoformat(),
        "expires_at": expires_at.isoformat(),
        "duration_minutes": duration_minutes,
        "client_ip": client_ip
    }
    _save_temp_data(data)

    return {
        "domain": domain.strip(),
        "expires_at": expires_at.isoformat(),
        "duration_minutes": duration_minutes,
        "remaining_seconds": duration_minutes * 60
    }

def remove_temp_domain(domain: str):
    """一時許可データから削除"""
    data = _load_temp_data()
    dom_key = domain.strip().lower()
    if dom_key in data:
        del data[dom_key]
        _save_temp_data(data)

def check_and_expire_temp_domains(reconfigure: bool = True) -> list[str]:
    """期限切れドメインを検出し、whitelist.txt から削除して Squid を再読み込み"""
    now = datetime.now(timezone.utc)
    data = _load_temp_data()
    expired_domains = []

    for domain_key, info in list(data.items()):
        expires_at_iso = info.get("expires_at")
        if not expires_at_iso:
            continue
        try:
            expires_at = datetime.fromisoformat(expires_at_iso)
            if now >= expires_at:
                expired_domains.append(info.get("domain", domain_key))
                del data[domain_key]
        except Exception:
            del data[domain_key]

    if not expired_domains:
        return []

    _save_temp_data(data)

    # whitelist.txt から期限切れドメインを削除
    if os.path.exists(WHITELIST_FILE):
        try:
            with open(WHITELIST_FILE, "r", encoding="utf-8") as f:
                lines = f.readlines()

            new_lines = []
            removed = False
            for line in lines:
                clean_dom = line.strip().lstrip("#").strip()
                if clean_dom.lower() in [d.lower() for d in expired_domains]:
                    removed = True
                    continue
                new_lines.append(line)

            if removed:
                with open(WHITELIST_FILE, "w", encoding="utf-8") as f:
                    f.writelines(new_lines)
        except Exception as e:
            print(f"Error removing expired temp domains from whitelist: {e}")

    # Squid 再設定とログ記録
    reconfig_msg = "スキップ"
    if reconfigure:
        _ok, reconfig_msg = reconfigure_squid()

    for exp_dom in expired_domains:
        log_control_operation(
            action="whitelist_temporary_expired",
            details=f"一時許可期限切れにより自動削除: {exp_dom} ({reconfig_msg})",
            client_ip="system"
        )

    return expired_domains

async def temp_whitelist_watcher_loop():
    """バックグラウンド監視ループ (10秒間隔)"""
    while True:
        try:
            check_and_expire_temp_domains(reconfigure=True)
        except Exception as e:
            print(f"Error in temp whitelist watcher: {e}")
        await asyncio.sleep(10)
