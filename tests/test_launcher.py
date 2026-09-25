import os
import sys

import pytest

# binディレクトリをPythonパスに追加してlauncherモジュールをインポートできるようにする
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'bin')))
import launcher


def test_build_command_goose_cli():
    env, cmd = launcher.build_command("run_goose_cli")
    assert "USE_GPU" not in env
    assert "RM" not in env
    assert cmd == ["make", "session"]

def test_build_command_goose_gui():
    env, cmd = launcher.build_command("run_goose_gui")
    assert cmd == ["make", "gui"]

def test_build_command_opencode_cli():
    env, cmd = launcher.build_command("run_opencode_cli")
    assert cmd == ["make", "run-opencode"]

def test_build_command_opencode_gui():
    env, cmd = launcher.build_command("run_opencode_gui")
    assert cmd == ["make", "run-opencode-gui"]

def test_build_command_openclaw_cli():
    env, cmd = launcher.build_command("run_openclaw_cli")
    assert cmd == ["make", "run-openclaw"]

def test_build_command_openclaw_gui():
    env, cmd = launcher.build_command("run_openclaw_gui")
    assert cmd == ["make", "run-openclaw-gui"]

def test_build_command_with_gpu():
    env, cmd = launcher.build_command("run_goose_cli", use_gpu=True)
    assert env.get("USE_GPU") == "1"
    assert cmd == ["make", "session"]

def test_build_command_with_keep_container():
    env, cmd = launcher.build_command("run_goose_cli", keep_container=True)
    assert env.get("RM") == "0"
    assert cmd == ["make", "session"]

def test_build_command_with_all_options():
    env, cmd = launcher.build_command("run_opencode_cli", use_gpu=True, keep_container=True, recreate=True)
    assert env.get("USE_GPU") == "1"
    assert env.get("RM") == "0"
    assert cmd == ["make", "run-opencode"]

def test_build_command_recreate():
    env, cmd = launcher.build_command("recreate")
    assert cmd == ["make", "recreate"]

def test_build_command_management_commands():
    env, cmd = launcher.build_command("control")
    assert cmd == ["make", "control"]

    env, cmd = launcher.build_command("report")
    assert cmd == ["make", "report"]

    env, cmd = launcher.build_command("block_all")
    assert cmd == ["make", "block-all"]

    env, cmd = launcher.build_command("unblock")
    assert cmd == ["make", "unblock"]

    env, cmd = launcher.build_command("down")
    assert cmd == ["make", "down"]

    env, cmd = launcher.build_command("test")
    assert cmd == ["make", "test"]

def test_build_command_invalid_action():
    with pytest.raises(ValueError, match="不明なアクションです"):
        launcher.build_command("invalid_action_name")
