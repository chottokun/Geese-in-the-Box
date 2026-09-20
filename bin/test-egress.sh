#!/bin/bash
set -euo pipefail

# 依存コマンドの確認
for cmd in curl grep; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "エラー: 必須コマンド '$cmd' がインストールされていません。" >&2
        exit 1
    fi
done

# ==========================================
# Goose-in-the-Box 通信遮断テスト
# ==========================================
# Docker 内部ネットワークから実行する通信制御の検証スクリプト。
# Squid プロキシ (L7) + Docker internal-net (L3/L4) の2段構えを検証。

PROXY="${HTTP_PROXY:-http://egress-proxy:3128}"
PASS=0
FAIL=0

echo "=================================================="
echo " Goose-in-the-Box 通信遮断テスト"
echo " 接続先プロキシ: $PROXY"
echo "=================================================="

echo ""
echo "=== [1/5] ホワイトリストドメインのテスト (api.openai.com) ==="
if curl -s -I --proxy "$PROXY" https://api.openai.com 2>&1 | grep -q -E "HTTP/.* (200|401|404)"; then
    echo "  -> OK: プロキシ経由で接続許可"
    PASS=$((PASS + 1))
else
    echo "  -> FAIL: 想定外の応答（ホワイトリスト通信が遮断されています）"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "=== [2/5] 非許可ドメインのテスト (www.google.com) ==="
OUTPUT=$(curl -v --proxy "$PROXY" https://www.google.com 2>&1 || true)
if echo "$OUTPUT" | grep -q -E "403|Forbidden"; then
    echo "  -> OK: プロキシが 403 Forbidden で正常に遮断"
    PASS=$((PASS + 1))
else
    echo "  -> FAIL: 403 Forbidden が返されませんでした"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "=== [3/5] プロキシバイパス遮断のテスト (直接接続) ==="
if curl -s --connect-timeout 3 --noproxy "*" https://api.openai.com > /dev/null 2>&1; then
    echo "  -> CRITICAL: プロキシを迂回して外部接続に成功してしまいました！"
    FAIL=$((FAIL + 1))
else
    echo "  -> OK: internal ネットワークにより直接接続（バイパス）が正常に遮断されました"
    PASS=$((PASS + 1))
fi

echo ""
echo ""
echo "=== [4/5] host.docker.internal ポート制限テスト ==="
OUTPUT_OLLAMA=$(curl -s -I --proxy "$PROXY" http://host.docker.internal:11434 2>&1 || true)
if echo "$OUTPUT_OLLAMA" | grep -q -E "HTTP/.* (200|401|404|502|503|504)"; then
    echo "  -> OK: ポート 11434 (Ollama) への接続許可"
    PASS=$((PASS + 1))
else
    echo "  -> FAIL: ポート 11434 (Ollama) が拒否されました"
    FAIL=$((FAIL + 1))
fi

OUTPUT=$(curl -v --proxy "$PROXY" http://host.docker.internal:8080 2>&1 || true)
if echo "$OUTPUT" | grep -q -E "403|Forbidden"; then
    echo "  -> OK: ポート 8080 への接続が拒否されました"
    PASS=$((PASS + 1))
else
    echo "  -> FAIL: ポート 8080 への接続が許可されてしまいました"
    FAIL=$((FAIL + 1))
fi

echo ""
echo ""
echo "=== [5/5] 未許可ドメイン・キルスイッチ遮断テスト ==="
if curl -s -I --proxy "$PROXY" http://unauthorized.local 2>&1 | grep -q -E "403|Forbidden"; then
    echo "  -> OK: 未許可ドメインが期待通りに遮断されています"
    PASS=$((PASS + 1))
else
    echo "  -> FAIL: 未許可ドメインが遮断されませんでした"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "=================================================="
echo " テスト結果: $PASS 成功, $FAIL 失敗"
echo "=================================================="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
