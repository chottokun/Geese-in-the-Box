#!/bin/bash
set -euo pipefail

# 依存コマンドの確認
for cmd in openclaw python3; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "エラー: 必須コマンド '$cmd' がインストールされていません。" >&2
        exit 1
    fi
done

# ==========================================
# Geese-in-the-Box: OpenClaw CLI 起動スクリプト
# ==========================================
echo "=== OpenClaw CLI セッションを起動中 ==="

# LLM プロバイダー設定の同期 (~/.openclaw/openclaw.json)
echo "環境変数から OpenClaw 設定 (~/.openclaw/openclaw.json) を同期..."
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
    if '/' not in configured_model:
        if openai_key:
            configured_model = f'openai/{configured_model}'
        elif anthropic_key:
            configured_model = f'anthropic/{configured_model}'
        elif google_key:
            configured_model = f'google/{configured_model}'
    elif not any(configured_model.startswith(p + '/') for p in ['openai', 'anthropic', 'google', 'groq', 'openrouter', 'ollama', 'minimax']):
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
" || true

GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-}"
if [ -z "$GATEWAY_TOKEN" ]; then
    # トークン未設定時はランダムトークンを自動生成
    GATEWAY_TOKEN=$(head -c 16 /dev/urandom | xxd -p 2>/dev/null || od -A n -t x -N 16 /dev/urandom | tr -d ' ' 2>/dev/null || echo "openclaw-sandbox-token")
    export OPENCLAW_GATEWAY_TOKEN="$GATEWAY_TOKEN"
fi

cd /workspace

if [ $# -eq 0 ]; then
    exec openclaw tui --local
elif [ "$1" = "tui" ]; then
    shift
    exec openclaw tui --local "$@"
elif [ "$1" = "openclaw" ]; then
    shift
    if [ "${1:-}" = "tui" ]; then
        shift
        exec openclaw tui --local "$@"
    else
        exec openclaw "$@"
    fi
else
    exec openclaw "$@"
fi

