import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'bin')))
import os
import subprocess

import launcher
import yaml


def test_start_scripts_exist_and_syntax():
    """起動スクリプトの存在とbash構文チェック (bash -n)"""
    scripts = [
        "bin/start-goose.sh",
        "bin/start-desktop.sh",
        "bin/start-opencode-desktop.sh",
        "bin/start-openclaw.sh",
        "bin/start-openclaw-desktop.sh",
    ]
    for script in scripts:
        assert os.path.exists(script), f"{script} が見つかりません"

        # bash -n による構文チェック
        result = subprocess.run(["bash", "-n", script], capture_output=True, text=True)
        assert result.returncode == 0, f"{script} の構文エラー:\n{result.stderr}"

def test_makefile_targets_exist():
    """Makefileに必要なターゲットが存在し、期待するコマンドを含んでいるか"""
    assert os.path.exists("Makefile"), "Makefile が見つかりません"

    with open("Makefile", "r", encoding="utf-8") as f:
        content = f.read()

    targets = {
        "session": "bin/start-goose.sh",
        "gui": "up -d",
        "run-opencode": "opencode",
        "run-opencode-gui": "bin/start-opencode-desktop.sh",
        "run-openclaw": "bin/start-openclaw.sh",
        "run-openclaw-gui": "bin/start-openclaw-desktop.sh",
    }

    for target, expected_cmd in targets.items():
        assert f"\n{target}:" in content or f"^{target}:" in content or f" {target}:" in content, f"Makefile にターゲット {target} がありません"
        assert expected_cmd in content, f"Makefile の {target} ターゲット付近に {expected_cmd} が見つかりません"

def test_docker_compose_mounts():
    """docker-compose.yml で必要な起動スクリプトがマウントされているか"""
    assert os.path.exists("docker-compose.yml"), "docker-compose.yml が見つかりません"

    with open("docker-compose.yml", "r", encoding="utf-8") as f:
        compose_data = yaml.safe_load(f)

    services = compose_data.get("services", {})

    # Goose
    goose_svc = services.get("goose-agent", {})
    goose_volumes = goose_svc.get("volumes", [])
    assert any("bin/start-goose.sh" in v for v in goose_volumes), "goose-agent サービスに start-goose.sh がマウントされていません"
    assert any("bin/start-desktop.sh" in v for v in goose_volumes), "goose-agent サービスに start-desktop.sh がマウントされていません"

    # OpenCode
    opencode_svc = services.get("opencode", {})
    opencode_volumes = opencode_svc.get("volumes", [])
    assert any("bin/start-opencode-desktop.sh" in v for v in opencode_volumes), "opencode サービスに start-opencode-desktop.sh がマウントされていません"

    # OpenClaw
    openclaw_svc = services.get("openclaw", {})
    openclaw_volumes = openclaw_svc.get("volumes", [])
    assert any("bin/start-openclaw.sh" in v for v in openclaw_volumes), "openclaw サービスに start-openclaw.sh がマウントされていません"
    assert any("bin/start-openclaw-desktop.sh" in v for v in openclaw_volumes), "openclaw サービスに start-openclaw-desktop.sh がマウントされていません"




def test_launcher_targets_match_makefile():
    """bin/launcher.py のメニュー項目から生成されるコマンドが Makefile の対応するターゲットと一致することを検証"""
    assert launcher.build_command("run_goose_cli")[1] == ["make", "session"]
    assert launcher.build_command("run_goose_gui")[1] == ["make", "gui"]
    assert launcher.build_command("run_opencode_cli")[1] == ["make", "run-opencode"]
    assert launcher.build_command("run_opencode_gui")[1] == ["make", "run-opencode-gui"]
    assert launcher.build_command("run_openclaw_cli")[1] == ["make", "run-openclaw"]
    assert launcher.build_command("run_openclaw_gui")[1] == ["make", "run-openclaw-gui"]
