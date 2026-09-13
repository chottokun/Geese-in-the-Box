#!/bin/bash
# bin/audit-tools.sh
# 監査ログ集計・可視化ツール群 (Docker コンテナ連携)

set -euo pipefail

PROXY_CONTAINER="egress-proxy"
LOG_PATH="/var/log/squid/access.json"

show_help() {
    echo "使用方法: $0 <command>"
    echo ""
    echo "コマンド:"
    echo "  denied      拒否された通信を一覧表示"
    echo "  domains     送信先ドメインの集計（アクセス頻度・転送量順）"
    echo "  violations  不正な接続試行（未許可ポート、未許可メソッド等）のサマリー"
    echo ""
}

check_proxy() {
    if ! docker compose ps -q "$PROXY_CONTAINER" >/dev/null 2>&1; then
        echo "エラー: $PROXY_CONTAINER コンテナが起動していません。" >&2
        echo "起動コマンド: make up-proxy" >&2
        exit 1
    fi
}

cmd_denied() {
    check_proxy
    echo "=== 拒否された通信の一覧 (403 DENIED) ==="
    docker compose exec -T "$PROXY_CONTAINER" cat "$LOG_PATH" 2>/dev/null \
        | jq -r 'select(.squid_status | test("DENIED")) | [.time, .client, .method, .domain, .url] | @tsv' || echo "ログがまだありません"
}

cmd_domains() {
    check_proxy
    echo "=== 送信先ドメイン集計 (頻度順トップ20) ==="
    docker compose exec -T "$PROXY_CONTAINER" cat "$LOG_PATH" 2>/dev/null \
        | jq -r '.domain' | grep -v '^-$$' | sort | uniq -c | sort -rn | head -20 || echo "ログがまだありません"
    echo ""
    echo "=== 送信先ドメイン集計 (転送量順・単位: Bytes) ==="
    docker compose exec -T "$PROXY_CONTAINER" cat "$LOG_PATH" 2>/dev/null \
        | jq -r '[.domain, .bytes_sent + .bytes_received] | @tsv' \
        | awk '{arr[$1]+=$2} END {for (i in arr) {if (i != "-") print arr[i]"\t"i}}' | sort -rn | head -20 || echo "ログがまだありません"
}

cmd_violations() {
    check_proxy
    echo "=== 不正な接続試行サマリー ==="
    echo ""
    echo "--- 拒否されたステータスコード ---"
    docker compose exec -T "$PROXY_CONTAINER" cat "$LOG_PATH" 2>/dev/null \
        | jq -r 'select(.squid_status | test("DENIED")) | .status' | sort | uniq -c | sort -rn || true
    echo ""
    echo "--- ブロックされたドメイン (トップ10) ---"
    docker compose exec -T "$PROXY_CONTAINER" cat "$LOG_PATH" 2>/dev/null \
        | jq -r 'select(.squid_status | test("DENIED")) | .domain' | sort | uniq -c | sort -rn | head -10 || true
    echo ""
    echo "--- ブロックされたHTTPメソッド ---"
    docker compose exec -T "$PROXY_CONTAINER" cat "$LOG_PATH" 2>/dev/null \
        | jq -r 'select(.squid_status | test("DENIED")) | .method' | sort | uniq -c | sort -rn || true
}

case "${1:-help}" in
    denied)
        cmd_denied
        ;;
    domains)
        cmd_domains
        ;;
    violations)
        cmd_violations
        ;;
    *)
        show_help
        exit 1
        ;;
esac
