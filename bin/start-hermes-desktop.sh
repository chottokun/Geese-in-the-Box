#!/bin/bash
set -euo pipefail

# shellcheck disable=SC1091
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/lib/desktop-common.sh" ]; then
    # shellcheck source=bin/lib/desktop-common.sh
    source "${SCRIPT_DIR}/lib/desktop-common.sh"
elif [ -f "/bin/host-scripts/lib/desktop-common.sh" ]; then
    # shellcheck source=bin/lib/desktop-common.sh
    source "/bin/host-scripts/lib/desktop-common.sh"
elif [ -f "/bin/lib/desktop-common.sh" ]; then
    source "/bin/lib/desktop-common.sh"
else
    echo "エラー: desktop-common.sh が見つかりません。" >&2
    exit 1
fi

# 1. デスクトップ環境の起動 (ポート 6084)
init_desktop_environment 6084

# 2. Xfce4 ターミナルで Hermes を起動
echo "Hermes CLI を起動します..."
sleep 2
xfce4-terminal -e /home/sandboxuser/.local/bin/hermes &

# 3. 監視ループ
wait_desktop_termination 6084
