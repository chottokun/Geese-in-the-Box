#!/bin/bash
set -e

# ==========================================
# Goose-in-the-Box 通信遮断テスト
# ==========================================
# VM 内で実行する通信制御の検証スクリプト。
# Squid プロキシ + iptables の 2 段構えが正常に機能しているか検証する。

PROXY="http://127.0.0.1:3128"
PASS=0
FAIL=0

echo "=== [1/4] ホワイトリストドメインのテスト (api.openai.com) ==="
if curl -s -I --proxy "$PROXY" https://api.openai.com 2>&1 | grep -q -E "HTTP/.* (200|401|404)"; then
    echo "  -> OK: プロキシ経由で接続許可"
    ((PASS++))
else
    echo "  -> FAIL: 想定外の応答"
    ((FAIL++))
fi

echo ""
echo "=== [2/4] 非許可ドメインのテスト (www.google.com) ==="
OUTPUT=$(curl -v --proxy "$PROXY" https://www.google.com 2>&1 || true)
if echo "$OUTPUT" | grep -q -E "403|Forbidden"; then
    echo "  -> OK: プロキシが 403 Forbidden で遮断"
    ((PASS++))
else
    echo "  -> FAIL: 403 が返されなかった"
    ((FAIL++))
fi

echo ""
echo "=== [3/4] プロキシバイパスのテスト (直接接続) ==="
if curl -s --connect-timeout 3 --noproxy "*" https://api.openai.com > /dev/null 2>&1; then
    echo "  -> CRITICAL: プロキシを迂回して外部接続に成功！"
    ((FAIL++))
else
    echo "  -> OK: iptables が直接接続を遮断"
    ((PASS++))
fi

echo ""
echo "=== [4/4] 監査ログ記録のテスト ==="
if [ -f /var/log/squid/access.json ] && [ -s /var/log/squid/access.json ]; then
    LAST_ENTRY=$(tail -1 /var/log/squid/access.json)
    if echo "$LAST_ENTRY" | jq . > /dev/null 2>&1; then
        echo "  -> OK: JSON 監査ログが正常に記録されている"
        echo "  -> 最新エントリ: $LAST_ENTRY"
        ((PASS++))
    else
        echo "  -> FAIL: ログが JSON として不正"
        ((FAIL++))
    fi
else
    echo "  -> FAIL: 監査ログファイルが存在しないか空"
    ((FAIL++))
fi

echo ""
echo "=== テスト完了: $PASS 成功, $FAIL 失敗 ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
