#!/bin/bash
set -e

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
echo "=== [1/3] ホワイトリストドメインのテスト (api.openai.com) ==="
if curl -s -I --proxy "$PROXY" https://api.openai.com 2>&1 | grep -q -E "HTTP/.* (200|401|404)"; then
    echo "  -> OK: プロキシ経由で接続許可"
    PASS=$((PASS + 1))
else
    echo "  -> FAIL: 想定外の応答（ホワイトリスト通信が遮断されています）"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "=== [2/3] 非許可ドメインのテスト (www.google.com) ==="
OUTPUT=$(curl -v --proxy "$PROXY" https://www.google.com 2>&1 || true)
if echo "$OUTPUT" | grep -q -E "403|Forbidden"; then
    echo "  -> OK: プロキシが 403 Forbidden で正常に遮断"
    PASS=$((PASS + 1))
else
    echo "  -> FAIL: 403 Forbidden が返されませんでした"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "=== [3/3] プロキシバイパス遮断のテスト (直接接続) ==="
if curl -s --connect-timeout 3 --noproxy "*" https://api.openai.com > /dev/null 2>&1; then
    echo "  -> CRITICAL: プロキシを迂回して外部接続に成功してしまいました！"
    FAIL=$((FAIL + 1))
else
    echo "  -> OK: internal ネットワークにより直接接続（バイパス）が完全に遮断されました"
    PASS=$((PASS + 1))
fi

echo ""
echo "=================================================="
echo " テスト結果: $PASS 成功, $FAIL 失敗"
echo "=================================================="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
