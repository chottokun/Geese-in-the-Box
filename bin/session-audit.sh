#!/bin/bash
# bin/session-audit.sh
# 過去のログも含めてセッション（日付）ごとの通信傾向を比較表示する

set -euo pipefail

# 依存コマンドの確認
for cmd in jq awk cut grep sort uniq wc head; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "エラー: 必須コマンド '$cmd' がインストールされていません。" >&2
        exit 1
    fi
done

LOG_DIR="logs/squid"
echo "=== セッション別通信サマリー ==="
printf "%-15s %-8s %-8s %-12s %-20s\n" "日付" "許可" "遮断" "総バイト(MB)" "トップドメイン"
echo "----------------------------------------------------------------------"

# 日付順にソートして処理
shopt -s nullglob
files=("$LOG_DIR"/access.json*)
shopt -u nullglob

for file in "${files[@]}"; do
    if [ ! -s "$file" ]; then continue; fi

    # ファイル内の先頭のログから日付を抽出 (YYYY-MM-DD)
    DATE_STR=$(head -1 "$file" | jq -r '.time' | cut -d'T' -f1 || echo "Unknown")
    
    ALLOWED=$(jq -r 'select(.squid_status | test("DENIED") | not)' "$file" | wc -l)
    DENIED=$(jq -r 'select(.squid_status | test("DENIED"))' "$file" | wc -l)
    
    # バイト数の合計 (MB単位)
    TOTAL_BYTES=$(jq -r '.bytes_sent + .bytes_received' "$file" | awk '{s+=$1} END {printf "%.1f", s/1048576}')
    
    # トップドメイン
    TOP_DOMAIN=$(jq -r '.domain' "$file" | grep -v '^-' | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
    
    printf "%-15s %-8s %-8s %-12s %-20s\n" "$DATE_STR" "$ALLOWED" "$DENIED" "${TOTAL_BYTES} MB" "${TOP_DOMAIN:--}"
done
