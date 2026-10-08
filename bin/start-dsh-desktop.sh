#!/bin/bash
set -euo pipefail

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

# 1. デスクトップ環境の起動 (ポート 6083)
init_desktop_environment 6083

# 2. DSH Web サーバーのバックグラウンド起動
echo "DSH Web サーバーを起動しています..."
(
    cd /opt/dsh
    node ./lib/cli.js web --host 127.0.0.1 --port 4000
) &
DSH_PID=$!

# 3. 少し待ってから Chromium を起動
sleep 5
echo "Chromium を起動して DSH を開きます..."
chromium --no-sandbox http://127.0.0.1:4000 &

# 4. 監視ループ
wait_desktop_termination 6083
