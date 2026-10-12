import asyncio
import os
from datetime import datetime, timedelta, timezone

from app import storage
from app.audit import log_control_operation
from app.squid_service import reconfigure_squid

DATA_DIR = os.getenv("DATA_DIR", "/app/data")
TEMP_WHITELIST_FILE = os.path.join(DATA_DIR, ".temp_whitelist.json")
WHITELIST_FILE = os.path.join(DATA_DIR, "whitelist.txt")

JST = timezone(timedelta(hours=9))


def _load_temp_data() -> dict[str, dict]:
    return storage.load_temp_data(TEMP_WHITELIST_FILE)


def _save_temp_data(data: dict[str, dict]) -> None:
    storage.save_temp_data(data, TEMP_WHITELIST_FILE)


def get_temp_domains_info() -> dict[str, dict]:
    return storage.get_temp_domains_info(TEMP_WHITELIST_FILE)


def register_temp_domain(domain: str, duration_minutes: int, client_ip: str = "unknown") -> dict:
    return storage.register_temp_domain(domain, duration_minutes, client_ip, TEMP_WHITELIST_FILE)


def remove_temp_domain(domain: str) -> None:
    storage.remove_temp_domain(domain, TEMP_WHITELIST_FILE)


def check_and_expire_temp_domains(reconfigure: bool = True) -> list[str]:
    """期限切れドメインを検出し、whitelist.txt から削除して Squid を再読み込み"""
    now = datetime.now(timezone.utc)
    data = storage.load_temp_data(TEMP_WHITELIST_FILE)
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

    storage.save_temp_data(data, TEMP_WHITELIST_FILE)

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


async def temp_whitelist_watcher_loop() -> None:
    """バックグラウンド監視ループ (10秒間隔)"""
    while True:
        try:
            check_and_expire_temp_domains(reconfigure=True)
        except Exception as e:
            print(f"Error in temp whitelist watcher: {e}")
        await asyncio.sleep(10)
