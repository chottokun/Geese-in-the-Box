#!/bin/bash
set -euo pipefail

# ==========================================
# Goose セッション起動スクリプト
# ==========================================
# AGENTS.md / CLAUDE.md のルールを自動読み込みして Goose CLI セッションを開始する。

WORKSPACE="${GOOSE_WORKSPACE:-/workspace}"
cd "$WORKSPACE"

SYSTEM_CONTENT=""

# 1. メインの指示ファイル（AGENTS.md または CLAUDE.md）の読み込み
if [ -f "AGENTS.md" ]; then
    echo "ロード中: AGENTS.md をルールとして適用します"
    SYSTEM_CONTENT="$(cat AGENTS.md)"
elif [ -f "CLAUDE.md" ]; then
    echo "ロード中: CLAUDE.md をルールとして適用します"
    SYSTEM_CONTENT="$(cat CLAUDE.md)"
fi

# 2. 分割ルールファイル (.agents/rules/*.md, .rules/*.md) の読み込み・結合
shopt -s nullglob
RULE_FILES=(.agents/rules/*.md .rules/*.md)
shopt -u nullglob

if [ ${#RULE_FILES[@]} -gt 0 ]; then
    for rule_file in "${RULE_FILES[@]}"; do
        if [ -f "$rule_file" ]; then
            echo "ロード中: $rule_file をルールとして追加適用します"
            if [ -n "$SYSTEM_CONTENT" ]; then
                SYSTEM_CONTENT="${SYSTEM_CONTENT}

$(cat "$rule_file")"
            else
                SYSTEM_CONTENT="$(cat "$rule_file")"
            fi
        fi
    done
fi

# システムプロンプト引数の組み立て
SYSTEM_ARGS=()
if [ -n "$SYSTEM_CONTENT" ]; then
    SYSTEM_ARGS=(--system "$SYSTEM_CONTENT")
fi

exec goose session "${SYSTEM_ARGS[@]}" "$@"
