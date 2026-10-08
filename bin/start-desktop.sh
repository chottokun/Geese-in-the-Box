#!/bin/bash
set -euo pipefail

# ==========================================
# Geese-in-the-Box: Goose GUI / noVNC 起動スクリプト
# ==========================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/lib/desktop-common.sh" ]; then
    # shellcheck source=bin/lib/desktop-common.sh
    source "${SCRIPT_DIR}/lib/desktop-common.sh"
elif [ -f "/bin/host-scripts/lib/desktop-common.sh" ]; then
    # shellcheck source=bin/lib/desktop-common.sh
    source "/bin/host-scripts/lib/desktop-common.sh"
else
    echo "エラー: desktop-common.sh が見つかりません。" >&2
    exit 1
fi

echo "=== Goose Desktop 隔離 GUI 環境を起動中 ==="

# デスクトップ基盤の初期化 (ポート: 6080)
init_desktop_environment 6080

# 7. Goose Desktop GUI アプリの自動起動
echo "7. Goose Desktop GUI アプリを起動 (作業ディレクトリ: /workspace)..."
cd /workspace
if [ -f /usr/lib/goose/Goose ]; then
    /usr/lib/goose/Goose &
elif command -v goose >/dev/null 2>&1; then
    echo "注意: Goose GUI バイナリが見つからないため、ターミナルでCLIを起動できる状態にします。"
    xfce4-terminal &
else
    echo "警告: Goose のバイナリが見つかりません。GUIは起動しますがGooseアプリは自動起動しません。"
fi

# デスクトップ環境の維持・監視
wait_desktop_termination 6080
