#!/bin/bash
# bin/watch-alerts.sh
# リアルタイムアラート監視スクリプト
# SquidのJSONログを監視し、DENIED通信を検出してアラートを表示します。

set -eo pipefail

LOG_FILE="logs/squid/access.json"
WEBHOOK_URL="${ALERT_WEBHOOK_URL:-}"

# 色の定義
RED='\033[0;31m'
YELLOW='\033[0;33m'
RESET='\033[0m'

echo -e "${YELLOW}=== アラート監視を開始します ===${RESET}"
echo "監視対象: ${LOG_FILE}"
if [ -n "$WEBHOOK_URL" ]; then
    echo "Webhook通知: 有効 (${WEBHOOK_URL})"
else
    echo "Webhook通知: 無効 (ALERT_WEBHOOK_URLが未設定)"
fi
echo -e "-----------------------------------\n"

# ログファイルが存在しない場合は空で作成
if [ ! -f "$LOG_FILE" ]; then
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
fi

# 前回のDENIEDドメインと時刻を記録（ストーム抑制用）
LAST_DOMAIN=""
LAST_TIME=0
SUPPRESS_SECONDS=5

tail -F -n 0 "$LOG_FILE" | while read -r line; do
    # JSONが正しくパースできるかチェック
    if ! echo "$line" | jq -e . >/dev/null 2>&1; then
        continue
    fi

    SQUID_STATUS=$(echo "$line" | jq -r '.squid_status')
    
    if [[ "$SQUID_STATUS" == *"DENIED"* ]]; then
        TIME=$(echo "$line" | jq -r '.time')
        DOMAIN=$(echo "$line" | jq -r '.domain')
        CLIENT=$(echo "$line" | jq -r '.client')
        METHOD=$(echo "$line" | jq -r '.method')
        URL=$(echo "$line" | jq -r '.url')
        
        CURRENT_TIME=$(date +%s)
        
        # ストーム抑制のチェック
        if [[ "$DOMAIN" == "$LAST_DOMAIN" ]] && (( CURRENT_TIME - LAST_TIME < SUPPRESS_SECONDS )); then
            continue
        fi
        
        LAST_DOMAIN="$DOMAIN"
        LAST_TIME="$CURRENT_TIME"

        # アラートの表示
        echo -e "${RED}[ALERT] 遮断された通信を検出しました${RESET}"
        echo -e "  時刻: ${TIME}"
        echo -e "  クライアント: ${CLIENT}"
        echo -e "  ドメイン: ${DOMAIN}"
        echo -e "  メソッド: ${METHOD}"
        echo -e "  URL: ${URL}\n"

        # Webhookへの送信
        if [ -n "$WEBHOOK_URL" ]; then
            PAYLOAD=$(jq -n \
                --arg text "🚨 遮断された通信を検出しました
- ドメイン: $DOMAIN
- 時刻: $TIME
- クライアント: $CLIENT
- メソッド: $METHOD
- URL: $URL" \
                '{text: $text}')
            
            curl -s -X POST -H 'Content-Type: application/json' -d "$PAYLOAD" "$WEBHOOK_URL" > /dev/null || echo -e "${YELLOW}Webhook送信に失敗しました${RESET}"
        fi
    fi
done
