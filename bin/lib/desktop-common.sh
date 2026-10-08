#!/bin/bash
# ==========================================================
# Geese-in-the-Box: 仮想デスクトップ (Xfce4 + noVNC) 共通基盤ライブラリ
# ==========================================================
# 各エージェントの start-*-desktop.sh から source して呼び出します。
# ==========================================================

set -euo pipefail

# 共通環境変数の初期化
export DISPLAY=:1
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
export SDL_IM_MODULE=fcitx
export ELECTRON_EXTRA_LAUNCH_ARGS="--no-sandbox"

# 依存コマンドの検証
check_desktop_prerequisites() {
    for cmd in Xvfb dbus-launch fcitx5 startxfce4 x11vnc websockify xargs grep awk; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "エラー: 必須コマンド '$cmd' がインストールされていません。" >&2
            exit 1
        fi
    done
}

# 終了ハンドラ
cleanup_desktop() {
    echo "=== 停止シグナルを受信しました。プロセスを終了します ==="
    pids=$(jobs -p)
    if [ -n "$pids" ]; then
        echo "$pids" | xargs -r kill 2>/dev/null || true
    fi
    exit 0
}

# デスクトップ環境の起動
# 引数: $1 = noVNCポート (例: 6080, 6081, 6082, 6083, 6084)
init_desktop_environment() {
    local novnc_port="${1:-6080}"
    local resolution="${RESOLUTION:-1280x800x24}"

    check_desktop_prerequisites
    trap cleanup_desktop SIGINT SIGTERM

    # 残存 X11 ロックファイルの削除 (コンテナ再起動対策)
    rm -f /tmp/.X1-lock /tmp/.X11-unix/X1

    # 1. 仮想フレームバッファ (Xvfb) の起動
    echo "1. Xvfb 仮想ディスプレイ (:1) を起動 (解像度: ${resolution})..."
    Xvfb :1 -screen 0 "$resolution" &
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

    # 5. VNC サーバー (x11vnc) の起動
    echo "5. x11vnc (port 5900) を起動..."
    x11vnc -display :1 -nopw -listen 0.0.0.0 -xkb -forever -shared &
    X11VNC_PID=$!
    sleep 1

    # 6. Webブラウザ接続用 noVNC (websockify) の起動
    echo "6. noVNC Webクライアント (port ${novnc_port}) を起動..."
    websockify --web /usr/share/novnc "$novnc_port" localhost:5900 &
    WEBSOCKIFY_PID=$!
    sleep 1
}

# 監視ループ (websockify または x11vnc が生存している間コンテナを維持)
wait_desktop_termination() {
    local novnc_port="${1:-6080}"
    echo "=========================================================="
    echo " GUI デスクトップが準備完了しました！"
    echo " ブラウザから接続: http://localhost:${novnc_port}/vnc.html"
    echo " 日本語入力切替: [Ctrl+Space] または [半角/全角]"
    echo "=========================================================="

    while kill -0 "$WEBSOCKIFY_PID" 2>/dev/null && kill -0 "$X11VNC_PID" 2>/dev/null; do
        sleep 2
    done
}
