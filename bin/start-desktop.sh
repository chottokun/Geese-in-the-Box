#!/bin/bash
set -euo pipefail

# ==========================================
# Goose-in-the-Box: GUI / noVNC 起動スクリプト
# ==========================================
echo "=== Goose Desktop 隔離 GUI 環境を起動中 ==="

# 画面解像度の設定
RESOLUTION="${RESOLUTION:-1280x800x24}"
export DISPLAY=:1
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

# 日本語入力システム (Fcitx5 + Mozc) の環境変数
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
export SDL_IM_MODULE=fcitx
# Electron アプリ用サンドボックス無効化設定
export ELECTRON_EXTRA_LAUNCH_ARGS="--no-sandbox"

# 終了ハンドラ
cleanup() {
    echo "=== 停止シグナルを受信しました。プロセスを終了します ==="
    pids=$(jobs -p)
    if [ -n "$pids" ]; then
        echo "$pids" | xargs -r kill 2>/dev/null || true
    fi
    exit 0
}
trap cleanup SIGINT SIGTERM

# 残存 X11 ロックファイルの削除 (コンテナ再起動対策)
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1

# 1. 仮想フレームバッファ (Xvfb) の起動
echo "1. Xvfb 仮想ディスプレイ (:1) を起動..."
Xvfb :1 -screen 0 "$RESOLUTION" &
# shellcheck disable=SC2034
XVFB_PID=$!
sleep 1

# 2. D-Bus セッションバスの起動
echo "2. D-Bus セッションバスを起動..."
eval "$(dbus-launch --sh-syntax)"
export DBUS_SESSION_BUS_ADDRESS
export DBUS_SESSION_BUS_PID

# 3. 日本語入力デーモン (Fcitx5) の起動
echo "3. Fcitx5 (日本語入力システム) を起動..."
fcitx5 -d --replace &
sleep 1

# 4. 軽量デスクトップ環境 (Xfce4) の起動
echo "4. Xfce4 デスクトップ環境を起動..."
startxfce4 &
sleep 2

# 5. VNC サーバー (x11vnc) の起動 (パスワードなしローカル接続)
echo "5. x11vnc (port 5900) を起動..."
x11vnc -display :1 -nopw -listen 0.0.0.0 -xkb -forever -shared &
X11VNC_PID=$!
sleep 1

# 6. Webブラウザ接続用 noVNC (websockify) の起動 (port 6080)
echo "6. noVNC Webクライアント (port 6080) を起動..."
websockify --web /usr/share/novnc 6080 localhost:5900 &
WEBSOCKIFY_PID=$!
sleep 1

# 7. Goose Desktop GUI アプリの自動起動
echo "7. Goose Desktop GUI アプリを起動 (作業ディレクトリ: /workspace)..."
cd /workspace
/usr/lib/goose/Goose &

echo "=========================================================="
echo " GUI デスクトップが準備完了しました！"
echo " ブラウザから接続: http://localhost:6080/vnc.html"
echo " 日本語入力切替: [Ctrl+Space] または [半角/全角]"
echo "=========================================================="

# 必須デーモン（websockify または x11vnc）を監視し、コンテナを常駐維持
while kill -0 "$WEBSOCKIFY_PID" 2>/dev/null && kill -0 "$X11VNC_PID" 2>/dev/null; do
    sleep 2
done
