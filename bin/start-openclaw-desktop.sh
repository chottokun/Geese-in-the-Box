#!/bin/bash
set -euo pipefail

# 依存コマンドの確認
for cmd in Xvfb dbus-launch fcitx5 startxfce4 x11vnc websockify xargs grep awk openclaw firefox; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "エラー: 必須コマンド '$cmd' がインストールされていません。" >&2
        exit 1
    fi
done

# ==========================================
# Goose-in-the-Box: OpenClaw GUI / noVNC 起動スクリプト
# ==========================================
echo "=== OpenClaw Desktop 隔離 GUI 環境を起動中 ==="

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

# 6. Webブラウザ接続用 noVNC (websockify) の起動 (port 6082)
echo "6. noVNC Webクライアント (port 6082) を起動..."
websockify --web /usr/share/novnc 6082 localhost:5900 &
WEBSOCKIFY_PID=$!
sleep 1

# 6.5. LLM プロバイダー設定の同期 (~/.openclaw/openclaw.json)
echo "6.5. 環境変数から OpenClaw 設定 (~/.openclaw/openclaw.json) を同期..."
mkdir -p /home/sandboxuser/.openclaw
python3 -c "
import json, os

config_path = '/home/sandboxuser/.openclaw/openclaw.json'
config = {}
if os.path.exists(config_path):
    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            config = json.load(f)
    except Exception:
        config = {}

# models セクションの構築
models = config.get('models', {})
models['mode'] = 'merge'
providers = models.get('providers', {})

# OpenAI / OpenAI互換 (さくらAI等)
openai_key = os.environ.get('OPENAI_API_KEY')
openai_base = os.environ.get('OPENAI_BASE_URL')
if openai_key or openai_base:
    p = providers.get('openai', {})
    if openai_key:
        p['apiKey'] = openai_key
    if openai_base:
        p['baseUrl'] = openai_base
    providers['openai'] = p

# Anthropic
anthropic_key = os.environ.get('ANTHROPIC_API_KEY')
if anthropic_key:
    providers['anthropic'] = {'apiKey': anthropic_key}

# Google (Gemini)
google_key = os.environ.get('GOOGLE_API_KEY')
if google_key:
    providers['google'] = {'apiKey': google_key}

# Groq
groq_key = os.environ.get('GROQ_API_KEY')
if groq_key:
    providers['groq'] = {'apiKey': groq_key}

# OpenRouter
openrouter_key = os.environ.get('OPENROUTER_API_KEY')
if openrouter_key:
    providers['openrouter'] = {'apiKey': openrouter_key}

# Ollama
ollama_host = os.environ.get('OLLAMA_HOST')
if ollama_host:
    providers['ollama'] = {'baseUrl': ollama_host}

models['providers'] = providers
config['models'] = models

# デフォルトモデルおよびワークスペースの設定
agents = config.get('agents', {})
defaults = agents.get('defaults', {})
defaults['workspace'] = '/workspace'

# モデルの決定: OPENCLAW_MODEL -> GOOSE_MODEL -> プロバイダー自動判定
configured_model = os.environ.get('OPENCLAW_MODEL') or os.environ.get('GOOSE_MODEL')

model_def = defaults.get('model', {})
if configured_model:
    # プレフィックスが指定されていない場合はプロバイダーを補完 (例: preview/Kimi... -> openai/preview/Kimi...)
    if '/' not in configured_model:
        if openai_key:
            configured_model = f'openai/{configured_model}'
        elif anthropic_key:
            configured_model = f'anthropic/{configured_model}'
        elif google_key:
            configured_model = f'google/{configured_model}'
    elif not any(configured_model.startswith(p + '/') for p in ['openai', 'anthropic', 'google', 'groq', 'openrouter', 'ollama', 'minimax']):
        # さくらAI等の独自パス (preview/... 等) の場合は openai/ を先頭に付与
        configured_model = f'openai/{configured_model}'
    model_def['primary'] = configured_model
else:
    if openai_key:
        model_def['primary'] = 'openai/gpt-4o'
    elif anthropic_key:
        model_def['primary'] = 'anthropic/claude-sonnet-4-20250514'
    elif google_key:
        model_def['primary'] = 'google/gemini-2.0-flash'

defaults['model'] = model_def
agents['defaults'] = defaults
config['agents'] = agents

with open(config_path, 'w', encoding='utf-8') as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
print(f'✓ LLM 設定を ~/.openclaw/openclaw.json に同期しました (Primary Model: {model_def.get(\"primary\")}, Workspace: /workspace)')
" || true

# 7. openclaw gateway をバックグラウンド起動
echo "7. openclaw gateway をバックグラウンドで起動..."
cd /workspace
GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-}"


# Dockerコンテナ環境では 0.0.0.0 (auto) へのバインドに認証 (token/password) が必須
if [ -z "$GATEWAY_TOKEN" ]; then
    # トークン未設定時はランダムトークンを自動生成
    GATEWAY_TOKEN=$(head -c 16 /dev/urandom | xxd -p 2>/dev/null || od -A n -t x -N 16 /dev/urandom | tr -d ' ' 2>/dev/null || echo "openclaw-sandbox-token")
    export OPENCLAW_GATEWAY_TOKEN="$GATEWAY_TOKEN"
    echo "※ OPENCLAW_GATEWAY_TOKEN を自動生成しました: ${GATEWAY_TOKEN}"
fi

# 残存した古い Gateway リースのクリーンアップ (コンテナ再起動・停止後の復帰用)
SQLITE_DB="/home/sandboxuser/.openclaw/state/openclaw.sqlite"
if [ -f "$SQLITE_DB" ]; then
    python3 -c "
import sqlite3
try:
    conn = sqlite3.connect('$SQLITE_DB')
    cur = conn.cursor()
    cur.execute(\"DELETE FROM state_leases WHERE scope = 'gateway-owner'\")
    conn.commit()
    conn.close()
    print('※ 残存していた Gateway リースをクリアしました')
except Exception as e:
    pass
" 2>/dev/null || true
fi

# ゲートウェイをバックグラウンド実行 (ingress-proxy からの転送を受け付けるため bind auto + token)
openclaw gateway run --force --port "$GATEWAY_PORT" --allow-unconfigured --auth token --token "$GATEWAY_TOKEN" &
sleep 4


# 8. firefox-esr で Control UI を開く (トークン認証付き)
echo "8. Firefox で Control UI を起動..."
firefox "http://localhost:${GATEWAY_PORT}/?token=${GATEWAY_TOKEN}" &



echo "=========================================================="
echo " GUI デスクトップが準備完了しました！"
echo " ブラウザから接続: http://localhost:6082/vnc.html"
echo " 日本語入力切替: [Ctrl+Space] または [半角/全角]"
echo "=========================================================="

# 必須デーモン（websockify または x11vnc）を監視し、コンテナを常駐維持
while kill -0 "$WEBSOCKIFY_PID" 2>/dev/null && kill -0 "$X11VNC_PID" 2>/dev/null; do
    sleep 2
done
