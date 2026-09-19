import os
import json
from datetime import datetime, timezone, timedelta
from fastapi import APIRouter, Depends, Query, Request
from pydantic import BaseModel
from typing import Optional, List, Any
from app.auth import get_current_user

router = APIRouter(prefix="/api", tags=["audit"])

LOGS_DIR = os.getenv("LOGS_DIR", "/app/logs")
AUDIT_FILE = os.path.join(LOGS_DIR, "control-panel-audit.json")
SQUID_LOG_FILE = os.path.join(LOGS_DIR, "squid/access.json")
STATUS_FILE = os.path.join(LOGS_DIR, "report/api/status.json")

JST = timezone(timedelta(hours=9))

def log_control_operation(
    action: str,
    details: str,
    client_ip: str,
    previous_state: Optional[str] = None,
    new_state: Optional[str] = None
):
    entry = {
        "time": datetime.now(JST).isoformat(),
        "action": action,
        "source_ip": client_ip,
        "details": details,
        "previous_state": previous_state,
        "new_state": new_state
    }
    try:
        os.makedirs(os.path.dirname(AUDIT_FILE), exist_ok=True)
        with open(AUDIT_FILE, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except Exception as e:
        print(f"Failed to write control panel audit log: {e}")

def read_reverse_lines(filepath: str, max_scan_lines: int = 5000, chunk_size: int = 65536):
    """
    ファイル末尾から逆順に行をイテレートするジェネレータ。
    巨大ログファイルでも全行メモリ展開を回避し、高速かつ省メモリで最新ログを取得する。
    """
    if not os.path.exists(filepath):
        return

    try:
        with open(filepath, "rb") as f:
            f.seek(0, os.SEEK_END)
            file_size = f.tell()
            if file_size == 0:
                return

            buffer = b""
            pointer = file_size
            lines_yielded = 0

            while pointer > 0 and lines_yielded < max_scan_lines:
                read_size = min(chunk_size, pointer)
                pointer -= read_size
                f.seek(pointer)
                chunk = f.read(read_size)
                buffer = chunk + buffer
                lines = buffer.split(b"\n")
                buffer = lines[0]  # 先頭の不完全行を次回チャンク用に保持

                for line in reversed(lines[1:]):
                    stripped = line.strip()
                    if stripped:
                        yield stripped.decode("utf-8", errors="replace")
                        lines_yielded += 1
                        if lines_yielded >= max_scan_lines:
                            return

            if buffer.strip() and lines_yielded < max_scan_lines:
                yield buffer.strip().decode("utf-8", errors="replace")
    except Exception as e:
        print(f"Error reading reverse lines from {filepath}: {e}")

@router.get("/status", dependencies=[Depends(get_current_user)])
def get_status():
    if os.path.exists(STATUS_FILE):
        try:
            with open(STATUS_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception as e:
            return {"error": f"ステータスファイルの読み込みに失敗しました: {e}"}
    return {
        "timestamp": datetime.now(JST).isoformat(),
        "summary": {"total_requests": 0, "allowed": 0, "denied": 0, "block_rate_pct": 0},
        "domains": [],
        "recent_denied": []
    }

@router.get("/logs", dependencies=[Depends(get_current_user)])
def get_logs(
    limit: int = Query(50, ge=1, le=500),
    filter_type: Optional[str] = Query(None, alias="filter")
):
    if not os.path.exists(SQUID_LOG_FILE):
        return {"logs": [], "total": 0}

    logs = []
    try:
        # 最大 limit * 10 行スキャン（フィルタ適用を考慮）
        max_scan = max(1000, limit * 10)
        for line in read_reverse_lines(SQUID_LOG_FILE, max_scan_lines=max_scan):
            try:
                entry = json.loads(line)
                if filter_type == "denied":
                    if "DENIED" not in entry.get("squid_status", "").upper():
                        continue
                elif filter_type == "allowed":
                    if "DENIED" in entry.get("squid_status", "").upper():
                        continue

                logs.append(entry)
                if len(logs) >= limit:
                    break
            except Exception:
                continue
    except Exception as e:
        return {"error": f"ログの取得に失敗しました: {e}", "logs": []}

    return {"logs": logs, "count": len(logs)}

@router.get("/audit/operations", dependencies=[Depends(get_current_user)])
def get_operation_audit(limit: int = Query(50, ge=1, le=200)):
    if not os.path.exists(AUDIT_FILE):
        return {"operations": []}

    operations = []
    try:
        for line in read_reverse_lines(AUDIT_FILE, max_scan_lines=limit * 2):
            try:
                operations.append(json.loads(line))
                if len(operations) >= limit:
                    break
            except Exception:
                continue
    except Exception as e:
        return {"error": f"操作ログの読み込みに失敗しました: {e}", "operations": []}

    return {"operations": operations}
