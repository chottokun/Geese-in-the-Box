#!/bin/bash
set -euo pipefail

# ==========================================
# Geese-in-the-Box: OpenCode GUI / noVNC 起動スクリプト
# ==========================================
# shellcheck disable=SC1091
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

echo "=== OpenCode Desktop 隔離 GUI 環境を起動中 ==="

# デスクトップ基盤の初期化 (ポート: 6081)
init_desktop_environment 6081

# 7. OpenCode Desktop GUI アプリの自動起動
echo "7. OpenCode Desktop GUI アプリを起動 (作業ディレクトリ: /workspace)..."
cd /workspace
if [ -f /usr/local/bin/opencode-desktop ]; then
    /usr/local/bin/opencode-desktop &
elif [ -f /opt/OpenCode/ai.opencode.desktop ]; then
    /opt/OpenCode/ai.opencode.desktop --no-sandbox &
elif command -v opencode >/dev/null 2>&1; then
    echo "注意: デスクトップGUIバイナリが見つからないため、ターミナルでCLIを起動できる状態にします。"
    xfce4-terminal &
else
    echo "警告: OpenCode のバイナリが見つかりません。GUIは起動しますがOpenCodeアプリは自動起動しません。"
fi

# デスクトップ環境の維持・監視
wait_desktop_termination 6081
