import os
import sys
from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient

# Add control-panel directory to sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../control-panel")))

import app.audit as audit_mod
import app.auth as auth_mod
import app.killswitch as killswitch_mod
import app.temp_whitelist as temp_whitelist_mod
import app.whitelist as whitelist_mod
from app.main import app


@pytest.fixture
def test_env(tmp_path):
    data_dir = tmp_path / "data"
    logs_dir = tmp_path / "logs"
    data_dir.mkdir()
    logs_dir.mkdir()

    wl_file = data_dir / "whitelist.txt"
    wl_file.write_text("example.com\n# disabled.com\n", encoding="utf-8")

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

    return {
        "client": TestClient(app, raise_server_exceptions=False),
        "data_dir": data_dir,
        "wl_file": wl_file,
    }


def test_auth_flow(test_env):
    client = test_env["client"]

    with patch.object(auth_mod, "IS_AUTH_ENABLED", True), \
         patch.object(auth_mod, "CONTROL_PANEL_PASSWORD", "secret123"):

        # 1. Unauthenticated request to protected endpoint
        res = client.get("/api/whitelist")
        assert res.status_code == 401
        assert res.json()["detail"] == "auth_required"

        # 2. Login with wrong password
        res = client.post("/api/auth/login", json={"password": "wrongpassword"})
        assert res.status_code == 401
        assert res.json()["detail"] == "invalid_password"

        # 3. Login with correct password
        res = client.post("/api/auth/login", json={"password": "secret123"})
        assert res.status_code == 200
        data = res.json()
        assert data["status"] == "ok"
        token = data["token"]
        assert token in auth_mod.SESSION_TOKENS

        # 4. Access protected endpoint with Bearer header
        res = client.get("/api/whitelist", headers={"Authorization": f"Bearer {token}"})
        assert res.status_code == 200

        # 5. Access status endpoint
        res = client.get("/api/auth/status", headers={"Authorization": f"Bearer {token}"})
        assert res.status_code == 200
        assert res.json()["authenticated"] is True

        # 6. Logout
        res = client.post("/api/auth/logout", headers={"Authorization": f"Bearer {token}"})
        assert res.status_code == 200
        assert token not in auth_mod.SESSION_TOKENS

        # 7. Access protected endpoint after logout
        res = client.get("/api/whitelist", headers={"Authorization": f"Bearer {token}"})
        assert res.status_code == 401


def test_whitelist_reload_endpoint(test_env):
    client = test_env["client"]
    res = client.post("/api/whitelist/reload")
    assert res.status_code == 200
    data = res.json()
    assert "status" in data
    assert "squid_reloaded" in data


def test_temp_whitelist_corrupted_json(test_env):
    data_dir = test_env["data_dir"]
    temp_file = data_dir / ".temp_whitelist.json"
    temp_file.write_text("INVALID JSON DATA", encoding="utf-8")

    # _load_temp_data should handle exception gracefully and return {}
    res = temp_whitelist_mod.get_temp_domains_info()
    assert res == {}


def test_temp_whitelist_readd_existing_disabled(test_env):
    client = test_env["client"]
    # Add temporary domain for disabled domain in whitelist.txt (# disabled.com)
    res = client.post("/api/whitelist/temporary", json={"domain": "disabled.com", "duration_minutes": 20})
    assert res.status_code == 200

    # Verify disabled.com is enabled now
    res = client.get("/api/whitelist")
    items = res.json()["domains"]
    target = next((d for d in items if d["domain"] == "disabled.com"), None)
    assert target is not None
    assert target["enabled"] is True
    assert target["is_temporary"] is True


def test_killswitch_unblock_without_backup(test_env):
    client = test_env["client"]
    wl_file = test_env["wl_file"]
    wl_file.write_text("line1.com\n# ALL BLOCKED\nline2.com\n", encoding="utf-8")

    res = client.post("/api/killswitch/unblock")
    assert res.status_code == 200

    content = wl_file.read_text(encoding="utf-8")
    assert "# ALL BLOCKED" not in content
    assert "line1.com" in content
    assert "line2.com" in content
