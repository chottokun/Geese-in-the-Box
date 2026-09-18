import sys
import os
import pytest
from fastapi.testclient import TestClient

# Add control-panel directory to sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../control-panel")))

from app.main import app
import app.whitelist as whitelist_mod
import app.killswitch as killswitch_mod
import app.audit as audit_mod
import app.temp_whitelist as temp_whitelist_mod

@pytest.fixture
def client(tmp_path):
    data_dir = tmp_path / "data"
    logs_dir = tmp_path / "logs"
    data_dir.mkdir()
    logs_dir.mkdir()

    wl_file = data_dir / "whitelist.txt"
    wl_file.write_text(".openai.com\ngithub.com\n", encoding="utf-8")

    # Patch module path variables
    whitelist_mod.DATA_DIR = str(data_dir)
    whitelist_mod.WHITELIST_FILE = str(wl_file)

    temp_whitelist_mod.DATA_DIR = str(data_dir)
    temp_whitelist_mod.WHITELIST_FILE = str(wl_file)
    temp_whitelist_mod.TEMP_WHITELIST_FILE = str(data_dir / ".temp_whitelist.json")

    killswitch_mod.DATA_DIR = str(data_dir)
    killswitch_mod.WHITELIST_FILE = str(wl_file)
    killswitch_mod.BACKUP_FILE = str(data_dir / ".whitelist.txt.bak")

    audit_mod.LOGS_DIR = str(logs_dir)
    audit_mod.AUDIT_FILE = str(logs_dir / "control-panel-audit.json")
    audit_mod.SQUID_LOG_FILE = str(logs_dir / "squid_access.json")
    audit_mod.STATUS_FILE = str(logs_dir / "status.json")

    return TestClient(app)

def test_health_check(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"

def test_whitelist_crud(client):
    # GET list
    res = client.get("/api/whitelist")
    assert res.status_code == 200
    domains = [d["domain"] for d in res.json()["domains"]]
    assert ".openai.com" in domains
    assert "github.com" in domains

    # POST add domain
    res = client.post("/api/whitelist", json={"domain": "pypi.org"})
    assert res.status_code == 200
    assert "pypi.org" in (res.json().get("message_ja", "") + res.json().get("domain", ""))

    # PATCH toggle domain (disable)
    res = client.patch("/api/whitelist/pypi.org", json={"enabled": False})
    assert res.status_code == 200

    res = client.get("/api/whitelist")
    pypi_item = next(d for d in res.json()["domains"] if d["domain"] == "pypi.org")
    assert pypi_item["enabled"] is False

    # DELETE domain
    res = client.delete("/api/whitelist/pypi.org")
    assert res.status_code == 200

    res = client.get("/api/whitelist")
    domains = [d["domain"] for d in res.json()["domains"]]
    assert "pypi.org" not in domains

def test_killswitch_flow(client):
    # Check initial status
    res = client.get("/api/killswitch")
    assert res.status_code == 200
    assert res.json()["status"] == "online"

    # Block
    res = client.post("/api/killswitch/block")
    assert res.status_code == 200
    assert res.json()["status"] == "blocked"

    # Verify status
    res = client.get("/api/killswitch")
    assert res.json()["status"] == "blocked"

    # Unblock
    res = client.post("/api/killswitch/unblock")
    assert res.status_code == 200
    assert res.json()["status"] == "online"

    # Verify status
    res = client.get("/api/killswitch")
    assert res.json()["status"] == "online"

def test_operation_audit_log(client):
    client.post("/api/whitelist", json={"domain": "test.com"})
    res = client.get("/api/audit/operations")
    assert res.status_code == 200
    ops = res.json()["operations"]
    assert len(ops) > 0
    assert ops[0]["action"] == "whitelist_add"

def test_spa_index_route(client):
    res = client.get("/")
    assert res.status_code == 200
    assert "Goose-in-the-Box コントロールパネル" in res.text

def test_temporary_whitelist_flow(client):
    # 1. 一時許可追加 (30分)
    res = client.post("/api/whitelist/temporary", json={"domain": "temp-api.example.com", "duration_minutes": 30})
    assert res.status_code == 200
    assert res.json()["status"] == "ok"
    assert "30 分間一時許可" in res.json()["message_ja"]

    # 2. ホワイトリスト一覧で is_temporary=True および remaining_seconds を確認
    res = client.get("/api/whitelist")
    assert res.status_code == 200
    domains = res.json()["domains"]
    target = next((d for d in domains if d["domain"] == "temp-api.example.com"), None)
    assert target is not None
    assert target["is_temporary"] is True
    assert target["duration_minutes"] == 30
    assert target["remaining_seconds"] > 0

    # 3. 期限切れシミュレーション (過去の日時に書き換えて check_and_expire を実行)
    data = temp_whitelist_mod._load_temp_data()
    assert "temp-api.example.com" in data
    # 期限を1秒前に設定
    from datetime import datetime, timezone, timedelta
    data["temp-api.example.com"]["expires_at"] = (datetime.now(timezone.utc) - timedelta(seconds=5)).isoformat()
    temp_whitelist_mod._save_temp_data(data)

    # 有効期限チェック実行 (Squidシグナルはスキップ)
    expired = temp_whitelist_mod.check_and_expire_temp_domains(reconfigure=False)
    assert "temp-api.example.com" in expired

    # 4. ホワイトリスト一覧から自動削除されていることを確認
    res = client.get("/api/whitelist")
    domains_after = [d["domain"] for d in res.json()["domains"]]
    assert "temp-api.example.com" not in domains_after

    # 5. 操作監査ログに自動削除が記録されていることを確認
    res = client.get("/api/audit/operations")
    actions = [op["action"] for op in res.json()["operations"]]
    assert "whitelist_temporary_add" in actions
    assert "whitelist_temporary_expired" in actions

def test_read_reverse_lines_and_log_filtering(client, tmp_path):
    import json
    logs_dir = tmp_path / "logs"
    squid_log = logs_dir / "squid_access.json"
    
    # 複数行のダミーSquidログを書き込む
    entries = [
        {"time": "2026-09-18T10:00:00+09:00", "squid_status": "TCP_TUNNEL/200", "domain": "allowed1.com"},
        {"time": "2026-09-18T10:01:00+09:00", "squid_status": "TCP_DENIED/403", "domain": "denied1.com"},
        {"time": "2026-09-18T10:02:00+09:00", "squid_status": "TCP_TUNNEL/200", "domain": "allowed2.com"},
        {"time": "2026-09-18T10:03:00+09:00", "squid_status": "TCP_DENIED/403", "domain": "denied2.com"}
    ]
    with open(squid_log, "w", encoding="utf-8") as f:
        for e in entries:
            f.write(json.dumps(e) + "\n")

    # 全ログ取得（最新が先頭に来る）
    res = client.get("/api/logs?limit=10")
    assert res.status_code == 200
    logs = res.json()["logs"]
    assert len(logs) == 4
    assert logs[0]["domain"] == "denied2.com"

    # denied フィルタ
    res_denied = client.get("/api/logs?filter=denied&limit=10")
    assert res_denied.status_code == 200
    denied_logs = res_denied.json()["logs"]
    assert len(denied_logs) == 2
    assert denied_logs[0]["domain"] == "denied2.com"
    assert denied_logs[1]["domain"] == "denied1.com"

def test_purge_expired_tokens():
    import time
    import app.auth as auth_mod

    auth_mod.SESSION_TOKENS.clear()
    now = time.time()
    # 有効なトークン
    auth_mod.SESSION_TOKENS["valid_token"] = now + 1000
    # 期限切れトークン
    auth_mod.SESSION_TOKENS["expired_token_1"] = now - 10
    auth_mod.SESSION_TOKENS["expired_token_2"] = now - 50

    purged = auth_mod.purge_expired_tokens()
    assert purged == 2
    assert "valid_token" in auth_mod.SESSION_TOKENS
    assert "expired_token_1" not in auth_mod.SESSION_TOKENS
    assert "expired_token_2" not in auth_mod.SESSION_TOKENS

