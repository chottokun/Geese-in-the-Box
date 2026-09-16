#!/usr/bin/env bash
# bin/generate-report.sh
# Squid JSON 監査ログから可観測性ダッシュボード(HTML)・LLM用JSON API・Markdown要約を一括生成

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="${BASE_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

LOG_FILE="${BASE_DIR}/logs/squid/access.json"
PRICING_FILE="${BASE_DIR}/config/llm-pricing.json"
REPORT_DIR="${BASE_DIR}/logs/report"
API_DIR="${REPORT_DIR}/api"

mkdir -p "${API_DIR}"

if [ ! -f "${LOG_FILE}" ]; then
    echo "エラー: 監査ログファイル ${LOG_FILE} が見つかりません。" >&2
    exit 1
fi

if [ ! -r "${LOG_FILE}" ]; then
    chmod a+r "${LOG_FILE}" 2>/dev/null || sudo chmod a+r "${LOG_FILE}" 2>/dev/null || true
fi

if [ ! -f "${PRICING_FILE}" ]; then
    echo "エラー: 単価設定ファイル ${PRICING_FILE} が見つかりません。" >&2
    exit 1
fi

# Python 実行環境の判定 (uv が利用可能なら uv run、なければ python3 / python にフォールバック)
run_python() {
    if command -v uv >/dev/null 2>&1; then
        uv run --directory "${BASE_DIR}" python -
    elif command -v python3 >/dev/null 2>&1; then
        python3 -
    elif command -v python >/dev/null 2>&1; then
        python -
    else
        echo "エラー: Python 実行環境 (uv / python3 / python) が見つかりません。" >&2
        exit 1
    fi
}

run_python << 'PYEOF'
import json
import os
import sys
from datetime import datetime
from collections import Counter, defaultdict

base_dir = os.environ.get("BASE_DIR") or os.path.abspath(os.path.join(os.path.dirname(__file__) if "__file__" in locals() else ".", "."))
log_file = os.path.join(base_dir, "logs/squid/access.json")
pricing_file = os.path.join(base_dir, "config/llm-pricing.json")
report_dir = os.path.join(base_dir, "logs/report")
api_dir = os.path.join(report_dir, "api")

with open(pricing_file, "r", encoding="utf-8") as f:
    pricing_config = json.load(f)

usd_to_jpy = pricing_config.get("usd_to_jpy", 150)
thresholds = pricing_config.get("thresholds", {
    "deny_rate_warn_percent": 15.0,
    "deny_rate_crit_percent": 30.0,
    "single_transfer_warn_bytes": 1048576,
    "total_cost_warn_usd": 10.0
})
provider_map = pricing_config.get("providers", {})

# 集計変数
total_requests = 0
allowed_requests = 0
denied_requests = 0
start_time = None
end_time = None

domain_counts = Counter()
user_agent_counts = Counter()
recent_denials = []
large_requests = []

# LLM統計: domain -> dict
llm_stats = defaultdict(lambda: {
    "count": 0,
    "bytes_sent": 0,
    "bytes_received": 0,
    "durations": []
})

with open(log_file, "r", encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except Exception:
            continue

        total_requests += 1
        t = entry.get("time", "")
        if not start_time and t:
            start_time = t
        if t:
            end_time = t

        domain = entry.get("domain", "-")
        method = entry.get("method", "-")
        url = entry.get("url", "-")
        status = entry.get("status", 0)
        squid_status = entry.get("squid_status", "")
        bytes_sent = int(entry.get("bytes_sent") or 0)
        bytes_received = int(entry.get("bytes_received") or 0)
        duration_ms = int(entry.get("duration_ms") or 0)
        ua = entry.get("user_agent") or "null"

        is_denied = "DENIED" in squid_status or (status == 403)
        if is_denied:
            denied_requests += 1
            if len(recent_denials) < 20:
                recent_denials.append({
                    "time": t,
                    "method": method,
                    "domain": domain,
                    "url": url,
                    "status": status
                })
        else:
            allowed_requests += 1

        if domain and domain != "-":
            domain_counts[domain] += 1
        user_agent_counts[ua] += 1

        # 大容量通信チェック
        total_transfer = bytes_sent + bytes_received
        if total_transfer >= thresholds.get("single_transfer_warn_bytes", 1048576):
            large_requests.append({
                "time": t,
                "domain": domain,
                "bytes_sent": bytes_sent,
                "bytes_received": bytes_received,
                "total_bytes": total_transfer,
                "duration_ms": duration_ms
            })

        # LLMプロバイダー判定
        matched_provider_domain = None
        for p_dom in provider_map.keys():
            if domain == p_dom or domain.endswith("." + p_dom):
                matched_provider_domain = p_dom
                break

        if matched_provider_domain:
            st = llm_stats[matched_provider_domain]
            st["count"] += 1
            st["bytes_sent"] += bytes_sent
            st["bytes_received"] += bytes_received
            st["durations"].append(duration_ms)

# 計算サマリー
deny_rate = (denied_requests / total_requests * 100.0) if total_requests > 0 else 0.0

llm_provider_results = []
total_est_cost_usd = 0.0
total_est_tokens = 0

for p_dom, p_conf in provider_map.items():
    st = llm_stats.get(p_dom)
    if not st or st["count"] == 0:
        continue

    cnt = st["count"]
    b_sent = st["bytes_sent"]
    b_recv = st["bytes_received"]
    avg_dur = int(sum(st["durations"]) / len(st["durations"])) if st["durations"] else 0

    # トークン概算推計 (暗号化通信の概算。オーダー推定)
    # bytes_received (クライアント -> Squid) から HTTP オーバーヘッド除外
    # 1リクエストあたり約800bytes差し引く
    eff_sent = max(0, b_sent - (cnt * 500))
    eff_recv = max(0, b_recv - (cnt * 800))

    # prompt: 送信バイト数 ≒ 3.75 bytes/token
    prompt_tokens = int(eff_recv / 3.75)
    # completion: 受信バイト数 (SSE等20%除外) ≒ 3.25 bytes/token
    completion_tokens = int((eff_sent * 0.80) / 3.25)
    tokens_sum = prompt_tokens + completion_tokens

    cost_in = (prompt_tokens / 1_000_000.0) * p_conf.get("input_per_1m_usd", 0.0)
    cost_out = (completion_tokens / 1_000_000.0) * p_conf.get("output_per_1m_usd", 0.0)
    cost_usd = cost_in + cost_out
    cost_jpy = int(round(cost_usd * usd_to_jpy))

    total_est_cost_usd += cost_usd
    total_est_tokens += tokens_sum

    llm_provider_results.append({
        "provider": p_conf.get("name", p_dom),
        "domain": p_dom,
        "request_count": cnt,
        "bytes_sent_total": b_sent,
        "bytes_received_total": b_recv,
        "estimated_prompt_tokens": prompt_tokens,
        "estimated_completion_tokens": completion_tokens,
        "estimated_total_tokens": tokens_sum,
        "estimated_cost_usd": round(cost_usd, 4),
        "estimated_cost_jpy": cost_jpy,
        "avg_duration_ms": avg_dur,
        "note": p_conf.get("note", "")
    })

total_est_cost_jpy = int(round(total_est_cost_usd * usd_to_jpy))

# アラート判定 (LLMが迷わないよう事前評価)
alerts = []
if deny_rate >= thresholds.get("deny_rate_crit_percent", 30.0):
    alerts.append({
        "type": "high_deny_rate",
        "severity": "critical",
        "message": f"通信遮断率が危険域です ({deny_rate:.1f}% >= 30%)。不正なリクエストまたはホワイトリスト不備を確認してください。"
    })
elif deny_rate >= thresholds.get("deny_rate_warn_percent", 15.0):
    alerts.append({
        "type": "high_deny_rate",
        "severity": "warning",
        "message": f"通信遮断率がやや高めです ({deny_rate:.1f}% >= 15%)。"
    })

if total_est_cost_usd >= thresholds.get("total_cost_warn_usd", 10.0):
    alerts.append({
        "type": "cost_spike",
        "severity": "warning",
        "message": f"LLM推定利用コストが閾値を超過しました (${total_est_cost_usd:.2f} >= ${thresholds.get('total_cost_warn_usd'):.2f})。"
    })

if len(large_requests) > 0:
    alerts.append({
        "type": "large_transfer",
        "severity": "info",
        "message": f"1MB以上の大容量送受信が {len(large_requests)} 件検出されました。"
    })

# トップドメイン・UserAgentの整理
top_domains = [{"domain": d, "count": c} for d, c in domain_counts.most_common(15)]
top_uas = [{"user_agent": u, "count": c} for u, c in user_agent_counts.most_common(10)]

now_iso = datetime.now().astimezone().isoformat()

# 1. 構造化 JSON API 出力 (logs/report/api/status.json)
json_payload = {
    "generated_at": now_iso,
    "period": {
        "start": start_time or "N/A",
        "end": end_time or "N/A"
    },
    "summary": {
        "total_requests": total_requests,
        "allowed_requests": allowed_requests,
        "denied_requests": denied_requests,
        "deny_rate_percent": round(deny_rate, 2),
        "unique_domains": len(domain_counts)
    },
    "llm_usage": {
        "estimation_disclaimer": "Squid L7ログに基づく概算値 (TLS終端なしのため±50%程度の誤差を含む目安)",
        "total_estimated_tokens": total_est_tokens,
        "total_estimated_cost_usd": round(total_est_cost_usd, 4),
        "total_estimated_cost_jpy": total_est_cost_jpy,
        "providers": llm_provider_results
    },
    "alerts": alerts,
    "top_domains": top_domains,
    "top_user_agents": top_uas,
    "large_requests_count": len(large_requests),
    "top_costly_requests": sorted(large_requests, key=lambda x: x["total_bytes"], reverse=True)[:10],
    "recent_denials": recent_denials
}

json_path = os.path.join(api_dir, "status.json")
with open(json_path, "w", encoding="utf-8") as f:
    json.dump(json_payload, f, ensure_ascii=False, indent=2)

# 2. Markdown 要約出力 (logs/report/api/summary.md) - LLM コンテキストに最適
health_status = "✅ 正常 (Healthy)"
if any(a["severity"] == "critical" for a in alerts):
    health_status = "🚨 異常・要対処 (Critical)"
elif any(a["severity"] == "warning" for a in alerts):
    health_status = "⚠️ 警告・確認推奨 (Warning)"

md_lines = [
    f"# Goose-in-the-Box 監査サマリー ({now_iso[:19]})",
    "",
    f"### 総合状態: {health_status}",
    f"- **総リクエスト**: {total_requests:,} 件 (許可: {allowed_requests:,} / 遮断: {denied_requests:,} | 遮断率: {deny_rate:.2f}%)",
    f"- **監視期間**: `{start_time}` 〜 `{end_time}`",
    f"- **アクティブドメイン**: {len(domain_counts)} 件",
    f"- **LLM推定総コスト**: ¥{total_est_cost_jpy:,} (${total_est_cost_usd:.3f} USD) | 推定トークン: ~{total_est_tokens:,}",
    ""
]

if alerts:
    md_lines.append("### 検出されたアラート")
    for a in alerts:
        icon = "🚨" if a["severity"] == "critical" else ("⚠️" if a["severity"] == "warning" else "ℹ️")
        md_lines.append(f"- {icon} **[{a['type']}]** ({a['severity']}): {a['message']}")
    md_lines.append("")
else:
    md_lines.append("### アラート: なし (全システム正常)")
    md_lines.append("")

md_lines.append("### LLM プロバイダー別内訳 (概算 ±50%)")
if llm_provider_results:
    md_lines.append("| プロバイダー | ドメイン | 呼出数 | 推定トークン | 推定コスト | 平均所要時間 |")
    md_lines.append("|:---|:---|---:|---:|---:|---:|")
    for p in llm_provider_results:
        md_lines.append(f"| {p['provider']} | `{p['domain']}` | {p['request_count']} | ~{p['estimated_total_tokens']:,} | ¥{p['estimated_cost_jpy']:,} (${p['estimated_cost_usd']:.3f}) | {p['avg_duration_ms']} ms |")
else:
    md_lines.append("*(LLM API 宛ての通信履歴はありません)*")
md_lines.append("")

md_lines.append("### 上位アクセスドメイン (Top 5)")
for d in top_domains[:5]:
    md_lines.append(f"- `{d['domain']}`: {d['count']} 回")
md_lines.append("")

if recent_denials:
    md_lines.append(f"### 直近遮断された通信 (直近 {min(5, len(recent_denials))} 件)")
    for dn in recent_denials[:5]:
        md_lines.append(f"- `{dn['time']}`: {dn['method']} `{dn['domain']}` (URL: {dn['url']})")
    md_lines.append("")

md_path = os.path.join(api_dir, "summary.md")
with open(md_path, "w", encoding="utf-8") as f:
    f.write("\n".join(md_lines))

# 3. HTML 視覚ダッシュボード出力 (logs/report/index.html)
# 人間向けモダンUI、自動更新、Dozzle / noVNC へのナビゲーションリンク付き
html_content = f"""<!DOCTYPE html>
<html lang="ja">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="refresh" content="30">
    <title>Goose-in-the-Box 監査・可観測性ダッシュボード</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;600&display=swap" rel="stylesheet">
    <style>
        :root {{
            --bg-color: #0d1117;
            --card-bg: #161b22;
            --border-color: #30363d;
            --text-main: #c9d1d9;
            --text-muted: #8b949e;
            --accent-blue: #58a6ff;
            --accent-green: #3fb950;
            --accent-red: #f85149;
            --accent-yellow: #d29922;
            --accent-purple: #bc8cff;
        }}
        * {{ box-sizing: border-box; margin: 0; padding: 0; }}
        body {{
            font-family: 'Inter', sans-serif;
            background-color: var(--bg-color);
            color: var(--text-main);
            padding: 24px;
            line-height: 1.5;
        }}
        header {{
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding-bottom: 20px;
            border-bottom: 1px solid var(--border-color);
            margin-bottom: 24px;
            flex-wrap: wrap;
            gap: 16px;
        }}
        h1 {{ font-size: 22px; font-weight: 700; color: #fff; display: flex; align-items: center; gap: 10px; }}
        .badge {{
            display: inline-block;
            padding: 4px 10px;
            border-radius: 12px;
            font-size: 12px;
            font-weight: 600;
        }}
        .badge-healthy {{ background: rgba(63, 185, 80, 0.2); color: var(--accent-green); border: 1px solid var(--accent-green); }}
        .badge-warn {{ background: rgba(210, 153, 34, 0.2); color: var(--accent-yellow); border: 1px solid var(--accent-yellow); }}
        .badge-crit {{ background: rgba(248, 81, 73, 0.2); color: var(--accent-red); border: 1px solid var(--accent-red); }}
        
        .nav-links {{ display: flex; gap: 12px; }}
        .nav-link {{
            color: var(--accent-blue);
            text-decoration: none;
            padding: 6px 14px;
            background: var(--card-bg);
            border: 1px solid var(--border-color);
            border-radius: 6px;
            font-size: 13px;
            font-weight: 500;
            transition: all 0.2s;
        }}
        .nav-link:hover {{ background: #21262d; border-color: var(--accent-blue); }}
        
        .meta-info {{ font-size: 12px; color: var(--text-muted); margin-bottom: 20px; }}
        
        .grid {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
            gap: 16px;
            margin-bottom: 24px;
        }}
        .card {{
            background: var(--card-bg);
            border: 1px solid var(--border-color);
            border-radius: 8px;
            padding: 16px;
        }}
        .card-label {{ font-size: 12px; color: var(--text-muted); text-transform: uppercase; letter-spacing: 0.5px; font-weight: 600; margin-bottom: 6px; }}
        .card-value {{ font-size: 26px; font-weight: 700; color: #fff; font-family: 'JetBrains Mono', monospace; }}
        .card-sub {{ font-size: 12px; color: var(--text-muted); margin-top: 4px; }}
        
        .section-title {{ font-size: 16px; font-weight: 600; color: #fff; margin: 24px 0 12px; display: flex; align-items: center; justify-content: space-between; }}
        
        table {{
            width: 100%;
            border-collapse: collapse;
            background: var(--card-bg);
            border: 1px solid var(--border-color);
            border-radius: 8px;
            overflow: hidden;
            margin-bottom: 24px;
            font-size: 13px;
        }}
        th, td {{
            padding: 12px 16px;
            text-align: left;
            border-bottom: 1px solid var(--border-color);
        }}
        th {{ background: #21262d; color: var(--text-muted); font-weight: 600; }}
        tr:last-child td {{ border-bottom: none; }}
        tr:hover {{ background: rgba(255, 255, 255, 0.02); }}
        code {{ font-family: 'JetBrains Mono', monospace; font-size: 12px; background: rgba(110, 118, 129, 0.2); padding: 2px 6px; border-radius: 4px; }}
        .text-right {{ text-align: right; }}
        .denied {{ color: var(--accent-red); font-weight: 600; }}
        
        .alert-box {{
            padding: 12px 16px;
            border-radius: 6px;
            margin-bottom: 20px;
            font-size: 13px;
            display: flex;
            align-items: center;
            gap: 10px;
        }}
        .alert-warning {{ background: rgba(210, 153, 34, 0.15); border: 1px solid var(--accent-yellow); color: var(--accent-yellow); }}
        .alert-critical {{ background: rgba(248, 81, 73, 0.15); border: 1px solid var(--accent-red); color: var(--accent-red); }}
        .alert-info {{ background: rgba(88, 166, 255, 0.15); border: 1px solid var(--accent-blue); color: var(--accent-blue); }}
    </style>
</head>
<body>

<header>
    <h1>
        <span>🛡️ Goose-in-the-Box 監査 & 可観測性ダッシュボード</span>
        <span class="badge { 'badge-healthy' if '正常' in health_status else ('badge-crit' if '異常' in health_status else 'badge-warn') }">{health_status}</span>
    </h1>
    <div class="nav-links">
        <a class="nav-link" href="/vnc.html" target="_blank">🖥️ noVNC 操作</a>
        <a class="nav-link" id="dozzle-link" href="#" target="_blank" onclick="this.href='//' + window.location.hostname + ':8080/';">📜 Dozzle ログ</a>
        <a class="nav-link" href="/report/api/status.json" target="_blank">🤖 JSON API</a>
        <a class="nav-link" href="/report/api/summary.md" target="_blank">📝 Markdown</a>
    </div>
    <script>
        document.addEventListener('DOMContentLoaded', function() {{
            var dl = document.getElementById('dozzle-link');
            if (dl) dl.href = '//' + window.location.hostname + ':8080/';
        }});
    </script>
</header>

<div class="meta-info">
    集計期間: <code>{start_time or 'N/A'}</code> 〜 <code>{end_time or 'N/A'}</code> | 最終更新: <code>{now_iso}</code> (30秒毎に自動更新)
</div>
"""

for a in alerts:
    sev_class = "alert-" + a["severity"]
    html_content += f'<div class="alert-box {sev_class}">⚠️ <strong>[{a["type"]}]</strong> {a["message"]}</div>'

html_content += f"""
<div class="grid">
    <div class="card">
        <div class="card-label">総リクエスト</div>
        <div class="card-value">{total_requests:,}</div>
        <div class="card-sub">Squid L7 プロキシ経由</div>
    </div>
    <div class="card">
        <div class="card-label">許可された通信</div>
        <div class="card-value" style="color: var(--accent-green);">{allowed_requests:,}</div>
        <div class="card-sub">ホワイトリスト適合</div>
    </div>
    <div class="card">
        <div class="card-label">遮断された通信</div>
        <div class="card-value" style="color: var(--accent-red);">{denied_requests:,}</div>
        <div class="card-sub">遮断率: {deny_rate:.2f}%</div>
    </div>
    <div class="card">
        <div class="card-label">LLM推定総コスト</div>
        <div class="card-value" style="color: var(--accent-purple);">¥{total_est_cost_jpy:,}</div>
        <div class="card-sub">${total_est_cost_usd:.3f} USD (推定トークン: ~{total_est_tokens:,})</div>
    </div>
</div>

<div class="section-title">
    <span>🤖 LLM API 使用量・推定コスト内訳</span>
    <span style="font-size: 12px; color: var(--text-muted); font-weight: normal;">※ TLS終端なしの概算値 (±50%誤差考慮)</span>
</div>
<table>
    <thead>
        <tr>
            <th>プロバイダー</th>
            <th>宛先ドメイン</th>
            <th class="text-right">呼出回数</th>
            <th class="text-right">推定入力トークン</th>
            <th class="text-right">推定出力トークン</th>
            <th class="text-right">推定コスト</th>
            <th class="text-right">平均所要時間</th>
            <th>備考</th>
        </tr>
    </thead>
    <tbody>
"""

if llm_provider_results:
    for p in llm_provider_results:
        html_content += f"""
        <tr>
            <td><strong>{p['provider']}</strong></td>
            <td><code>{p['domain']}</code></td>
            <td class="text-right">{p['request_count']}</td>
            <td class="text-right">{p['estimated_prompt_tokens']:,}</td>
            <td class="text-right">{p['estimated_completion_tokens']:,}</td>
            <td class="text-right"><strong>¥{p['estimated_cost_jpy']:,}</strong> <span style="color:var(--text-muted); font-size:11px;">(${p['estimated_cost_usd']:.3f})</span></td>
            <td class="text-right">{p['avg_duration_ms']:,} ms</td>
            <td style="color:var(--text-muted); font-size:12px;">{p['note']}</td>
        </tr>
"""
else:
    html_content += """<tr><td colspan="8" style="text-align:center; color:var(--text-muted);">LLM API 通信履歴はありません</td></tr>"""

html_content += """
    </tbody>
</table>

<div style="display: grid; grid-template-columns: 1fr 1fr; gap: 20px;">
    <div>
        <div class="section-title">🌐 宛先ドメイン アクセス頻度 Top 10</div>
        <table>
            <thead><tr><th>ドメイン</th><th class="text-right">回数</th></tr></thead>
            <tbody>
"""
for d in top_domains[:10]:
    html_content += f"""<tr><td><code>{d['domain']}</code></td><td class="text-right">{d['count']}</td></tr>"""

html_content += """
            </tbody>
        </table>
    </div>
    <div>
        <div class="section-title">🧩 User-Agent 内訳 Top 8</div>
        <table>
            <thead><tr><th>User-Agent</th><th class="text-right">回数</th></tr></thead>
            <tbody>
"""
for u in top_uas[:8]:
    html_content += f"""<tr><td><code>{u['user_agent']}</code></td><td class="text-right">{u['count']}</td></tr>"""

html_content += """
            </tbody>
        </table>
    </div>
</div>

<div class="section-title">🛑 遮断された通信 (直近 15 件)</div>
<table>
    <thead>
        <tr>
            <th>時刻</th>
            <th>メソッド</th>
            <th>ドメイン</th>
            <th>URL</th>
            <th>ステータス</th>
        </tr>
    </thead>
    <tbody>
"""
if recent_denials:
    for dn in recent_denials[:15]:
        html_content += f"""
        <tr>
            <td><code>{dn['time']}</code></td>
            <td><code>{dn['method']}</code></td>
            <td class="denied">{dn['domain']}</td>
            <td><code>{dn['url']}</code></td>
            <td><span class="badge badge-crit">{dn['status']}</span></td>
        </tr>
"""
else:
    html_content += """<tr><td colspan="5" style="text-align:center; color:var(--text-muted);">遮断された通信はありません</td></tr>"""

html_content += """
    </tbody>
</table>

</body>
</html>
"""

html_path = os.path.join(report_dir, "index.html")
with open(html_path, "w", encoding="utf-8") as f:
    f.write(html_content)

print(f"ダッシュボードを正常生成しました: {report_dir}")
PYEOF
