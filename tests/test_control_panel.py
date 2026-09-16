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
    assert "pypi.org" in res.json()["message"]

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
