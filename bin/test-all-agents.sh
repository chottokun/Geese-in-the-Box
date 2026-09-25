#!/bin/bash
set -euo pipefail

# ==========================================
# 全エージェントスモークテスト
# 各エージェントコンテナの起動スクリプトが正常に実行されるかテストする
# ==========================================

echo "=== Geese-in-the-Box スモークテストを開始 ==="

# プロキシコンテナの起動確認
echo "1. プロキシコンテナのヘルスチェック・起動..."
make up-proxy
sleep 2

# エラーカウント
ERRORS=0

# CLI テスト用関数（コマンドが正常終了 exit 0 することを確認）
test_cli_cmd() {
    local name="$1"
    local cmd="$2"
    echo -n "テスト: $name ... "
    if eval "$cmd" > /dev/null 2>&1; then
        echo "✅ OK"
    else
        echo "❌ FAILED"
        echo "コマンド実行失敗: $cmd"
        eval "$cmd" || true
        ERRORS=$((ERRORS + 1))
    fi
}

# GUI テスト用関数（バックグラウンド起動し稼働確認後に確実に停止・削除）
test_gui_cmd() {
    local name="$1"
    local cname="$2"
    local run_args="$3"
    local script="$4"
    echo -n "テスト: $name ... "

    # 既存の残存コンテナを掃除
    docker rm -f "$cname" >/dev/null 2>&1 || true

    # バックグラウンド起動
    if eval "docker compose $run_args run -d --name $cname $script" >/dev/null 2>&1; then
        sleep 4
        if [ "$(docker inspect -f '{{.State.Running}}' "$cname" 2>/dev/null)" = "true" ]; then
            echo "✅ OK (正常稼働確認)"
            docker rm -f "$cname" >/dev/null 2>&1 || true
        else
            echo "❌ FAILED (コンテナ異常終了)"
            docker logs "$cname" 2>&1 | tail -20 || true
            docker rm -f "$cname" >/dev/null 2>&1 || true
            ERRORS=$((ERRORS + 1))
        fi
    else
        echo "❌ FAILED (起動コマンド失敗)"
        ERRORS=$((ERRORS + 1))
    fi
}

echo "2. 各エージェント（Goose, OpenCode, OpenClaw）の起動検証を実施..."

# 1. Goose CLI
test_cli_cmd "Goose CLI (start-goose.sh)" "docker compose run --rm goose-agent /bin/start-goose.sh goose --version"

# 2. Goose GUI
test_gui_cmd "Goose GUI (start-desktop.sh)" "smoke-goose-gui" "" "goose-agent /bin/start-desktop.sh"

# 3. OpenCode CLI
test_cli_cmd "OpenCode CLI" "docker compose --profile opencode run --rm opencode opencode --version"

# 4. OpenCode GUI
test_gui_cmd "OpenCode GUI (start-opencode-desktop.sh)" "smoke-opencode-gui" "--profile opencode" "opencode /bin/start-opencode-desktop.sh"

# 5. OpenClaw CLI
test_cli_cmd "OpenClaw CLI (start-openclaw.sh)" "docker compose --profile openclaw run --rm openclaw /bin/start-openclaw.sh openclaw --version"

# 6. OpenClaw GUI
test_gui_cmd "OpenClaw GUI (start-openclaw-desktop.sh)" "smoke-openclaw-gui" "--profile openclaw" "openclaw /bin/start-openclaw-desktop.sh"

echo "=========================================="
if [ $ERRORS -gt 0 ]; then
    echo "=== スモークテスト失敗: $ERRORS 件のエラー ==="
    exit 1
else
    echo "=== スモークテスト完了: 全6組み合わせが正常にパスしました ==="
    exit 0
fi
