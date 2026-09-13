#!/bin/bash
set -e

echo "=== [1/3] Testing Whitelisted Domain (api.openai.com) via Proxy ==="
if curl -s -I --proxy http://egress-proxy:3128 https://api.openai.com | grep -q -E "HTTP/.* 200|HTTP/.* 404|HTTP/.* 401"; then
    echo "  -> OK: Connection allowed through proxy."
else
    echo "  -> Unexpected response (check proxy rules/network)."
fi

echo ""
echo "=== [2/3] Testing Blocked Domain (www.google.com) via Proxy ==="
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --proxy http://egress-proxy:3128 https://www.google.com || true)
if [ "$HTTP_CODE" = "403" ]; then
    echo "  -> OK: Blocked correctly by proxy (HTTP 403 Forbidden)."
else
    echo "  -> Warning: Expected 403, got $HTTP_CODE"
fi

echo ""
echo "=== [3/3] Testing Direct Egress (Bypassing Proxy) ==="
if curl -s --connect-timeout 3 --noproxy "*" https://api.openai.com > /dev/null 2>&1; then
    echo "  -> CRITICAL ALERT: Container escaped internal network!"
else
    echo "  -> OK: Direct egress completely blocked by internal-net."
fi

echo ""
echo "All validation tests finished."
