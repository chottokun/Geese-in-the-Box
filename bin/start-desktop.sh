#!/bin/bash
set -euo pipefail

# ==========================================
# Goose-in-the-Box: GUI / noVNC 起動スクリプト
# ==========================================
echo "=== Goose Desktop 隔離 GUI 環境を起動中 ==="

# 画面解像度の設定
RESOLUTION="${RESOLUTION:-1280x800x24}"
export DISPLAY=:1

# 終了ハンドラ
cleanup() {
    echo "=== 停止シグナルを受信しました。プロセスを終了します ==="
    kill $(jobs -p) 2>/dev/null || true
    exit 0
}
trap cleanup SIGINT SIGTERM

# 1. 仮想フレームバッファ (Xvfb) の起動
echo "1. Xvfb 仮想ディスプレイ (:1) を起動..."
Xvfb :1 -screen 0 "$RESOLUTION" &
XVFB_PID=$!
sleep 1

# 2. 軽量デスクトップ環境 (Xfce4) の起動
echo "2. Xfce4 デスクトップ環境を起動..."
startxfce4 &
sleep 2

# 3. VNC サーバー (x11vnc) の起動 (パスワードなしローカル接続)
echo "3. x11vnc (port 5900) を起動..."
x11vnc -display :1 -nopw -listen 0.0.0.0 -xkb -forever -shared &
X11VNC_PID=$!
sleep 1

# 4. Webブラウザ接続用 noVNC (websockify) の起動 (port 6080)
echo "4. noVNC Webクライアント (port 6080) を起動..."
websockify --web /usr/share/novnc 6080 localhost:5900 &
WEBSOCKIFY_PID=$!

echo "=========================================================="
echo " GUI デスクトップが準備完了しました！"
echo " ブラウザから接続: http://localhost:6080/vnc.html"
echo " VNCクライアントから接続: localhost:5900"
echo "=========================================================="

# 必須デーモン（websockify または x11vnc）を監視し、コンテナを常駐維持
while kill -0 "$WEBSOCKIFY_PID" 2>/dev/null && kill -0 "$X11VNC_PID" 2>/dev/null; do
    sleep 2
done
