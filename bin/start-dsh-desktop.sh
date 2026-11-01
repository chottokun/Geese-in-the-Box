#!/bin/bash
set -euo pipefail

# shellcheck disable=SC1091
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/lib/desktop-common.sh" ]; then
    source "${SCRIPT_DIR}/lib/desktop-common.sh"
elif [ -f "/bin/host-scripts/lib/desktop-common.sh" ]; then
    source "/bin/host-scripts/lib/desktop-common.sh"
elif [ -f "/bin/lib/desktop-common.sh" ]; then
    source "/bin/lib/desktop-common.sh"
else
    echo "エラー: desktop-common.sh が見つかりません。" >&2
    exit 1
fi

# 1. デスクトップ環境の起動 (ポート 6083)
init_desktop_environment 6083

# 2. DSH Web サーバーのバックグラウンド起動
echo "DSH Web サーバーを起動しています..."
(
    cd /opt/dsh
    node /opt/dsh/apps/cli/lib/bin.js web --host 127.0.0.1 --port 4000
) &

# 3. 少し待ってから Chromium を起動
sleep 5
echo "Chromium を起動して DSH を開きます..."
chromium --no-sandbox http://127.0.0.1:4000 &

# 4. 監視ループ
wait_desktop_termination 6083
