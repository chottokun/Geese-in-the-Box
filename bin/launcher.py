#!/usr/bin/env python3
"""
Geese-in-the-Box インタラクティブ CLI ランチャー
"""

import os
import subprocess
import sys
from typing import Dict, List, Tuple

try:
    import questionary
    from rich.console import Console
    from rich.panel import Panel
except ImportError:
    print("必要なパッケージがインストールされていません。")
    print("実行方法: uv run --with questionary --with rich python bin/launcher.py")
    sys.exit(1)

console = Console()

def build_command(action: str, use_gpu: bool = False, keep_container: bool = False, recreate: bool = False) -> Tuple[Dict[str, str], List[str]]:
    """
    ユーザーの選択に基づいて、実行する環境変数とコマンドリストを生成する。

    Args:
        action (str): 実行するアクションの識別子
        use_gpu (bool): GPU パススルーを有効にするかどうか
        keep_container (bool): コンテナを保持するかどうか
        recreate (bool): コンテナを強制再作成するかどうか

    Returns:
        Tuple[Dict[str, str], List[str]]: (環境変数の辞書, コマンド引数のリスト)
    """
    env_updates = {}
    cmd_args = ["make"]

    # オプションの設定
    if use_gpu:
        env_updates["USE_GPU"] = "1"

    if keep_container:
        env_updates["RM"] = "0"

    if recreate and action.startswith("run_"):
        # recreate オプションは起動系コマンドの前に行う。Makefile の都合上、ここでは make recreate のような
        # 複合コマンドではなく、個別に make recreate を実行する想定だが、
        # build_command の仕様上は1つのコマンドを返すため、ここでは環境変数は使わず、
        # recreate の場合は起動系コマンドに先立ってコンテナ破棄・再作成を行うなどが必要だが、
        # Makefile の仕組み上、コンテナ個別の再作成は `docker compose ... up --force-recreate` か `make recreate` を呼ぶ。
        # 今回の要件「recreate=True 指定時に適切な再作成コマンドが生成されること」に対応するため、
        # ここでは action に基づいて再作成コマンドを生成する。
        # 要件の "recreate=True 指定時に適切な再作成コマンドが生成されること" の解釈として、
        # 単純に "make recreate" を返す、もしくはオプションとして処理する。
        # 今回は一旦、アクション名に応じてコマンドを返す。
        pass

    # アクションに応じたコマンドの設定
    if action == "run_goose_cli":
        cmd_args.append("session")
    elif action == "run_goose_gui":
        cmd_args.append("gui")
    elif action == "run_opencode_cli":
        cmd_args.append("run-opencode")
    elif action == "run_opencode_gui":
        cmd_args.append("run-opencode-gui")
    elif action == "run_openclaw_cli":
        cmd_args.append("run-openclaw")
    elif action == "run_openclaw_gui":
        cmd_args.append("run-openclaw-gui")
    elif action == "control":
        cmd_args.append("control")
    elif action == "report":
        cmd_args.append("report")
    elif action == "block_all":
        cmd_args.append("block-all")
    elif action == "unblock":
        cmd_args.append("unblock")
    elif action == "down":
        cmd_args.append("down")
    elif action == "test":
        cmd_args.append("test")
    elif action == "recreate":
        # 特別なアクションとして recreate が呼ばれた場合
        cmd_args.append("recreate")
    else:
        raise ValueError(f"不明なアクションです: {action}")

    return env_updates, cmd_args

def main():
    console.print(Panel.fit(
        "[bold cyan]Geese-in-the-Box Interactive CLI Launcher[/bold cyan]\n"
        "AIエージェントの起動や管理コマンドを対話的に実行します。",
        title="🚀 Welcome"
    ))

    # メインメニューの選択肢
    menu_choices = [
        questionary.Choice("🚀 Goose (ターミナル)", value="run_goose_cli"),
        questionary.Choice("🚀 Goose (GUI)", value="run_goose_gui"),
        questionary.Choice("🚀 OpenCode (ターミナル)", value="run_opencode_cli"),
        questionary.Choice("🚀 OpenCode (GUI)", value="run_opencode_gui"),
        questionary.Choice("🚀 OpenClaw 2.0 (ターミナル)", value="run_openclaw_cli"),
        questionary.Choice("🚀 OpenClaw 2.0 (GUI)", value="run_openclaw_gui"),
        questionary.Separator(),
        questionary.Choice("🎛️  統合コントロールパネルの起動", value="control"),
        questionary.Choice("📊 監査レポート生成・表示", value="report"),
        questionary.Choice("🔒 緊急キルスイッチ操作 (全遮断)", value="block_all"),
        questionary.Choice("🔓 緊急キルスイッチ解除 (遮断解除)", value="unblock"),
        questionary.Choice("🛑 全コンテナの停止 (make down)", value="down"),
        questionary.Choice("🧪 通信遮断テストの実行 (make test)", value="test"),
        questionary.Separator(),
        questionary.Choice("🚪 終了", value="exit")
    ]

    try:
        action = questionary.select(
            "実行するアクションを選択してください:",
            choices=menu_choices
        ).ask()

        if action == "exit" or action is None:
            console.print("[yellow]終了します。[/yellow]")
            sys.exit(0)

        # 起動系コマンドの場合はオプションを聞く
        use_gpu = False
        keep_container = False
        recreate = False

        if action.startswith("run_"):
            options = questionary.checkbox(
                "起動オプションを選択してください (スペースで選択/解除、Enterで決定):",
                choices=[
                    questionary.Choice("⚡ GPU (NVIDIA CUDA) パススルー (USE_GPU=1)", value="gpu"),
                    questionary.Choice("💾 コンテナ状態保持 (RM=0: 変更内容を継続)", value="keep"),
                    questionary.Choice("🔄 コンテナ強制再作成 (recreate)", value="recreate"),
                ]
            ).ask()

            if options is None:
                console.print("[yellow]キャンセルされました。[/yellow]")
                sys.exit(0)

            use_gpu = "gpu" in options
            keep_container = "keep" in options
            recreate = "recreate" in options
    except (KeyboardInterrupt, EOFError):
        console.print("\n[yellow]操作がキャンセルされました。終了します。[/yellow]")
        sys.exit(0)

    # コマンドの構築
    # recreate の場合は先に make recreate を実行するか、どうするか。
    # 要件に「recreate=True 指定時に適切な再作成コマンドが生成されること」とあるので、
    # 実際には `build_command` 内で処理するか、2つのコマンドを実行するか。
    # シンプルにするため、recreate=True なら make recreate も実行するようにするか、
    # あるいは build_command が複数のコマンドを返すように設計するか。
    # 今回は、recreate 指定時は特別に make recreate を先に走らせる処理を追加。
    env_updates, cmd_args = build_command(action, use_gpu, keep_container)

    # 実際の環境変数辞書の作成
    run_env = os.environ.copy()
    run_env.update(env_updates)

    # 実行コマンドの表示
    env_str = " ".join([f"{k}={v}" for k, v in env_updates.items()])
    cmd_str = f"{env_str} {' '.join(cmd_args)}".strip()

    console.print(f"\n[bold green]実行するコマンド:[/bold green] {cmd_str}")

    if recreate:
        console.print("[bold yellow]ℹ️ 強制再作成(recreate)が選択されたため、先にコンテナを再作成します。[/bold yellow]")
        # recreate のためのコマンド
        rec_env, rec_cmd = build_command("recreate")
        rec_env_str = " ".join([f"{k}={v}" for k, v in rec_env.items()])
        rec_cmd_str = f"{rec_env_str} {' '.join(rec_cmd)}".strip()
        console.print(f"[bold green]事前コマンド:[/bold green] {rec_cmd_str}")

        try:
            subprocess.run(rec_cmd, env={**os.environ.copy(), **rec_env}, check=True)
        except subprocess.CalledProcessError as e:
            console.print(f"[bold red]再作成中にエラーが発生しました: {e}[/bold red]")
            sys.exit(e.returncode)
        except KeyboardInterrupt:
            console.print("\n[yellow]キャンセルされました。[/yellow]")
            sys.exit(0)

    # メインコマンドの実行
    try:
        subprocess.run(cmd_args, env=run_env, check=True)
    except subprocess.CalledProcessError as e:
        console.print(f"[bold red]コマンド実行中にエラーが発生しました: {e}[/bold red]")
        sys.exit(e.returncode)
    except KeyboardInterrupt:
        console.print("\n[yellow]実行がキャンセルされました。[/yellow]")
        sys.exit(0)

if __name__ == "__main__":
    main()
