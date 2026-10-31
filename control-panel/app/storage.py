import json
import os
import shutil
from datetime import datetime, timedelta, timezone
from typing import TypedDict

DATA_DIR = os.getenv("DATA_DIR", "/app/data")
WHITELIST_FILE = os.path.join(DATA_DIR, "whitelist.txt")
TEMP_WHITELIST_FILE = os.path.join(DATA_DIR, ".temp_whitelist.json")
BACKUP_FILE = os.path.join(DATA_DIR, ".whitelist.txt.bak")

JST = timezone(timedelta(hours=9))


class WhitelistItemDict(TypedDict, total=False):
    domain: str
    enabled: bool
    is_temporary: bool
    expires_at: str | None
    remaining_seconds: int | None
    duration_minutes: int | None


class TempDomainRecordDict(TypedDict):
    domain: str
    created_at: str
    expires_at: str
    duration_minutes: int
    client_ip: str


# --- Whitelist File Storage ---

def parse_whitelist_file(filepath: str | None = None) -> tuple[list[dict], list[str]]:
    target_file = filepath or WHITELIST_FILE
    items: list[dict] = []
    header_lines: list[str] = []
    if not os.path.exists(target_file):
        return items, header_lines

    try:
        with open(target_file, "r", encoding="utf-8") as f:
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


def write_whitelist_items(
    items: list[dict],
    header_lines: list[str] | None = None,
    filepath: str | None = None
) -> None:
    target_file = filepath or WHITELIST_FILE
    lines = list(header_lines) if header_lines else []
    for item in items:
        dom = item["domain"].strip()
        if item["enabled"]:
            lines.append(f"{dom}\n")
        else:
            lines.append(f"# {dom}\n")

    os.makedirs(os.path.dirname(target_file), exist_ok=True)
    with open(target_file, "w", encoding="utf-8") as f:
        f.writelines(lines)


# --- Temporary Whitelist Storage ---

def load_temp_data(filepath: str | None = None) -> dict[str, dict]:
    target_file = filepath or TEMP_WHITELIST_FILE
    if not os.path.exists(target_file):
        return {}
    try:
        with open(target_file, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        print(f"Failed to load temp whitelist file: {e}")
        return {}


def save_temp_data(data: dict[str, dict], filepath: str | None = None) -> None:
    target_file = filepath or TEMP_WHITELIST_FILE
    try:
        os.makedirs(os.path.dirname(target_file), exist_ok=True)
        with open(target_file, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
    except Exception as e:
        print(f"Failed to save temp whitelist file: {e}")


def get_temp_domains_info(filepath: str | None = None) -> dict[str, dict]:
    """現在の一時許可ドメイン情報（残り時間付き）を返却"""
    now = datetime.now(timezone.utc)
    data = load_temp_data(filepath)
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
                "is_expired": remaining_seconds <= 0,
            }
        except Exception:
            continue
    return result


def register_temp_domain(
    domain: str,
    duration_minutes: int,
    client_ip: str = "unknown",
    filepath: str | None = None
) -> dict:
    """ドメインを一時許可として登録"""
    now = datetime.now(timezone.utc)
    expires_at = now + timedelta(minutes=duration_minutes)

    data = load_temp_data(filepath)
    dom_key = domain.strip().lower()
    data[dom_key] = {
        "domain": domain.strip(),
        "created_at": now.isoformat(),
        "expires_at": expires_at.isoformat(),
        "duration_minutes": duration_minutes,
        "client_ip": client_ip,
    }
    save_temp_data(data, filepath)

    return {
        "domain": domain.strip(),
        "expires_at": expires_at.isoformat(),
        "duration_minutes": duration_minutes,
        "remaining_seconds": duration_minutes * 60,
    }


def remove_temp_domain(domain: str, filepath: str | None = None) -> None:
    """一時許可データから削除"""
    data = load_temp_data(filepath)
    dom_key = domain.strip().lower()
    if dom_key in data:
        del data[dom_key]
        save_temp_data(data, filepath)


# --- Killswitch Storage ---

def is_all_blocked(
    whitelist_file: str | None = None,
    backup_file: str | None = None
) -> bool:
    backup_f = backup_file or BACKUP_FILE
    wl_f = whitelist_file or WHITELIST_FILE

    if os.path.exists(backup_f):
        return True
    if os.path.exists(wl_f):
        try:
            with open(wl_f, "r", encoding="utf-8") as f:
                content = f.read()
                if "# ALL BLOCKED" in content or content.strip() == "# ALL BLOCKED":
                    return True
        except Exception:
            pass
    return False


def create_killswitch_backup(
    whitelist_file: str | None = None,
    backup_file: str | None = None
) -> bool:
    wl_f = whitelist_file or WHITELIST_FILE
    backup_f = backup_file or BACKUP_FILE
    if os.path.exists(wl_f) and not os.path.exists(backup_f):
        os.makedirs(os.path.dirname(backup_f), exist_ok=True)
        shutil.copy2(wl_f, backup_f)
        return True
    return False


def apply_block_all(whitelist_file: str | None = None) -> None:
    wl_f = whitelist_file or WHITELIST_FILE
    os.makedirs(os.path.dirname(wl_f), exist_ok=True)
    with open(wl_f, "w", encoding="utf-8") as f:
        f.write("# ALL BLOCKED\n")


def apply_unblock_all(
    whitelist_file: str | None = None,
    backup_file: str | None = None
) -> None:
    backup_f = backup_file or BACKUP_FILE
    wl_f = whitelist_file or WHITELIST_FILE

    if os.path.exists(backup_f):
        shutil.move(backup_f, wl_f)
    else:
        if os.path.exists(wl_f):
            with open(wl_f, "r", encoding="utf-8") as f:
                lines = f.readlines()
            new_lines = [line for line in lines if "# ALL BLOCKED" not in line]
            with open(wl_f, "w", encoding="utf-8") as f:
                f.writelines(new_lines)
