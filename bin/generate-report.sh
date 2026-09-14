#!/bin/bash
# bin/generate-report.sh
# JSON監査ログから静的HTMLレポートを生成する軽量スクリプト

set -euo pipefail

LOG_FILE="logs/squid/access.json"

if [ ! -f "$LOG_FILE" ]; then
    echo "エラー: ログファイル $LOG_FILE が見つかりません。" >&2
    # gracefully stop
    kill -INT $$ 
fi

# サマリー集計
TOTAL_REQ=$(cat "$LOG_FILE" | wc -l)
ALLOWED_REQ=$(cat "$LOG_FILE" | jq -r 'select(.squid_status | test("DENIED") | not)' | wc -l)
DENIED_REQ=$(cat "$LOG_FILE" | jq -r 'select(.squid_status | test("DENIED"))' | wc -l)
START_TIME=$(cat "$LOG_FILE" | head -1 | jq -r '.time' || echo "N/A")
END_TIME=$(cat "$LOG_FILE" | tail -1 | jq -r '.time' || echo "N/A")

# HTML出力
cat <<HTML
<!DOCTYPE html>
<html lang="ja">
<head>
    <meta charset="UTF-8">
    <title>Goose-in-the-Box 監査レポート</title>
    <style>
        body { font-family: sans-serif; background-color: #f4f4f9; color: #333; margin: 20px; }
        h1, h2 { color: #2c3e50; }
        .summary-box { background: white; padding: 15px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); display: flex; gap: 20px; margin-bottom: 20px; }
        .metric { text-align: center; }
        .metric-value { font-size: 24px; font-weight: bold; color: #2980b9; }
        table { width: 100%; border-collapse: collapse; background: white; box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin-bottom: 20px; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #34495e; color: white; }
        tr:hover { background-color: #f5f5f5; }
        .denied { color: #e74c3c; font-weight: bold; }
    </style>
</head>
<body>

<h1>Goose-in-the-Box 監査レポート</h1>
<p>期間: ${START_TIME} 〜 ${END_TIME}</p>

<div class="summary-box">
    <div class="metric"><div>総リクエスト数</div><div class="metric-value">${TOTAL_REQ}</div></div>
    <div class="metric"><div>許可されたリクエスト</div><div class="metric-value" style="color: #27ae60;">${ALLOWED_REQ}</div></div>
    <div class="metric"><div>遮断されたリクエスト</div><div class="metric-value" style="color: #e74c3c;">${DENIED_REQ}</div></div>
</div>

<h2>トップドメインアクセス (上位15件)</h2>
<table>
    <tr><th>ドメイン</th><th>アクセス回数</th></tr>
HTML

# トップドメイン集計
cat "$LOG_FILE" | jq -r '.domain' | grep -v '^-' | sort | uniq -c | sort -rn | head -15 | while read count domain; do
    echo "    <tr><td>${domain}</td><td>${count}</td></tr>"
done

cat <<HTML
</table>

<h2>User-Agent 内訳 (上位10件)</h2>
<table>
    <tr><th>User-Agent</th><th>アクセス回数</th></tr>
HTML

# User-Agent集計
cat "$LOG_FILE" | jq -r '.user_agent' | sort | uniq -c | sort -rn | head -10 | while read count ua; do
    echo "    <tr><td>${ua}</td><td>${count}</td></tr>"
done

cat <<HTML
</table>

<h2>遮断された通信 (直近20件)</h2>
<table>
    <tr><th>時刻</th><th>メソッド</th><th>ドメイン</th><th>URL</th></tr>
HTML

# 遮断された通信
cat "$LOG_FILE" | jq -r 'select(.squid_status | test("DENIED")) | [.time, .method, .domain, .url] | @tsv' | tail -20 | while IFS=$'\t' read -r time method domain url; do
    echo "    <tr><td>${time}</td><td>${method}</td><td class='denied'>${domain}</td><td>${url}</td></tr>"
done

cat <<HTML
</table>

</body>
</html>
HTML
