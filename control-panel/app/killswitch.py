import os
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, Request

from app import storage
from app.audit import log_control_operation
from app.auth import get_current_user
from app.squid_service import reconfigure_squid

router = APIRouter(prefix="/api/killswitch", tags=["killswitch"])

DATA_DIR = os.getenv("DATA_DIR", "/app/data")
WHITELIST_FILE = os.path.join(DATA_DIR, "whitelist.txt")
BACKUP_FILE = os.path.join(DATA_DIR, ".whitelist.txt.bak")

JST = timezone(timedelta(hours=9))


def is_all_blocked() -> bool:
    return storage.is_all_blocked(WHITELIST_FILE, BACKUP_FILE)


@router.get("", dependencies=[Depends(get_current_user)])
def get_killswitch_status():
    blocked = is_all_blocked()
    status = "blocked" if blocked else "online"

    last_updated = None
    target_file = BACKUP_FILE if os.path.exists(BACKUP_FILE) else WHITELIST_FILE
    if os.path.exists(target_file):
        mtime = os.path.getmtime(target_file)
        last_updated = datetime.fromtimestamp(mtime, tz=JST).isoformat()

    return {
        "status": status,
        "is_blocked": blocked,
        "last_updated": last_updated
    }


@router.post("/block", dependencies=[Depends(get_current_user)])
def block_all(request: Request):
    client_ip = request.client.host if request.client else "unknown"
    already_blocked = is_all_blocked()

    storage.create_killswitch_backup(WHITELIST_FILE, BACKUP_FILE)
    storage.apply_block_all(WHITELIST_FILE)

    reconfig_ok, reconfig_msg = reconfigure_squid()

    log_control_operation(
        action="killswitch_block",
        details=f"緊急キルスイッチ発動 (全通信遮断): {reconfig_msg}",
        client_ip=client_ip,
        previous_state="blocked" if already_blocked else "online",
        new_state="blocked"
    )

    return {
        "status": "blocked",
        "message": "blocked_all",
        "message_ja": "全通信を緊急遮断しました (ALL BLOCKED)",
        "message_en": "Emergency block applied to all network traffic (ALL BLOCKED)",
        "squid_reloaded": reconfig_ok
    }


@router.post("/unblock", dependencies=[Depends(get_current_user)])
def unblock_all(request: Request):
    client_ip = request.client.host if request.client else "unknown"
    was_blocked = is_all_blocked()

    storage.apply_unblock_all(WHITELIST_FILE, BACKUP_FILE)

    reconfig_ok, reconfig_msg = reconfigure_squid()

    log_control_operation(
        action="killswitch_unblock",
        details=f"通信遮断解除 (NORMAL): {reconfig_msg}",
        client_ip=client_ip,
        previous_state="blocked" if was_blocked else "online",
        new_state="online"
    )

    return {
        "status": "online",
        "message": "unblocked_all",
        "message_ja": "通信遮断を解除しました (ONLINE)",
        "message_en": "Traffic unblocked and resumed normal operation (ONLINE)",
        "squid_reloaded": reconfig_ok
    }
