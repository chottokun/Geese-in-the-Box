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
else
    echo "エラー: desktop-common.sh が見つかりません。" >&2
    exit 1
fi

echo "=== OpenClaw Desktop 隔離 GUI 環境を起動中 ==="

# デスクトップ基盤の初期化 (ポート: 6082)
init_desktop_environment 6082

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


# 8. デスクトップショートカットの作成
DESKTOP_DIR="/home/sandboxuser/Desktop"
mkdir -p "$DESKTOP_DIR"
CONTROL_UI_URL="http://localhost:${GATEWAY_PORT}/?token=${GATEWAY_TOKEN}"

cat <<EOF > "$DESKTOP_DIR/openclaw.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=OpenClaw Control UI
Comment=Open OpenClaw Control UI in Firefox
Exec=firefox "$CONTROL_UI_URL"
Icon=firefox-esr
Terminal=false
StartupNotify=true
Categories=Network;WebBrowser;
EOF
chmod +x "$DESKTOP_DIR/openclaw.desktop"

# 9. Gateway 起動待機 (ヘルスチェック)
echo "8. OpenClaw Gateway の起動を待機中..."
for i in $(seq 1 30); do
    if curl -s -f -o /dev/null "http://127.0.0.1:${GATEWAY_PORT}/" 2>/dev/null; then
        echo "✓ OpenClaw Gateway が正常に起動しました (試行: ${i}回目)"
        break
    fi
    sleep 1
done

# 10. firefox-esr で Control UI を開く (トークン認証付き)
echo "9. Firefox で Control UI を起動..."
firefox "$CONTROL_UI_URL" &



# デスクトップ環境の維持・監視
wait_desktop_termination 6082
