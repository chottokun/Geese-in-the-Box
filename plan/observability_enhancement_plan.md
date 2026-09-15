# 可観測性・分析（Observability）強化 実装計画書 (実装完了)

> **基本方針**:
> 1. **デュアルインターフェース (人間 & LLM)**: 
>    - 人間向け: Dozzle (8080) と HTML 監査レポートの動線を一本化し、Ingress プロキシ（Nginx ポート 6080）経由でグラフィカルダッシュボードをブラウザから常時閲覧・即時更新可能 (`/report/`)。
>    - LLM エージェント向け: パース負担とコンテキスト消費を最小化する **構造化 JSON API** (`/report/api/status.json`) と **Markdown 要約** (`/report/api/summary.md`) を並行出力。アラート（遮断率スパイクや大容量通信）は事前評価フラグとして埋め込み、LLMの幻覚・誤判定を防止。
> 2. **LLM トークン & コスト推計**: 
>    - SSL Bump（TLS 復号）を行わない安全な方針のまま、Squid の L7 監査ログ（バイト数・送受信比率・所要時間）に基づき、主要 LLM プロバイダーへの消費トークン概算と推定利用コストを可視化。
>    - 単価設定やアラート閾値は外部設定ファイル (`config/llm-pricing.json`) で管理。

---

## 1. 全体アーキテクチャ & 改良イメージ

```text
【ブラウザ（LAN / リモート / ローカル）】
   │
   ├─► http://<IP>:6080/vnc.html       --> Goose Desktop GUI (noVNC 画面操作)
   ├─► http://<IP>:6080/report/        --> 【新設】Nginx 配信 HTML 監査ダッシュボード
   │                                        (30秒自動リフレッシュ / Dozzle・noVNC への相互リンク)
   └─► http://<IP>:8080/               --> Dozzle リアルタイムログ

【LLM エージェント / 監視パイプライン】
   │
   ├─► curl http://<IP>:6080/report/api/status.json  --> 構造化 JSON (事前計算アラート・トークン・メトリクス)
   ├─► curl http://<IP>:6080/report/api/summary.md   --> Markdown 要約 (コンテキスト節約・ワンショット把握)
   └─► make report-json                              --> CLI から標準出力で即座に JSON 取得可能

【ログ・分析パイプライン】
   Squid 監査ログ (logs/squid/access.json) + 設定 (config/llm-pricing.json)
      │
      ▼
   bin/generate-report.sh (uv run python 高速解析エンジン)
      ├─ 総リクエスト、許可/遮断率、ドメイン別集計、User-Agent
      ├─ LLM 推定分析 (OpenAI / さくらAI / Anthropic / Google / Groq / Mistral)
      ├─ トークン推計 (Prompt ≒ 送信バイト除外補正, Completion ≒ 受信バイトSSE補正)
      ├─ 閾値評価に基づく自動アラート生成 (遮断率急増、コスト急増、大容量転送)
      │
      ▼
   logs/report/
      ├─ index.html          --> HTML 視覚ダッシュボード
      └─ api/
          ├─ status.json     --> 構造化 JSON API
          └─ summary.md      --> Markdown テキスト要約
```

---

## 2. 実装詳細

### 機能 1: Web ダッシュボードと HTML レポートのシームレス統合
- **Nginx 設定 (`nginx/nginx.conf`)**:
  - `server (listen 6080)` 内に `location /report/` を追加。
  - キャッシュ無効化ヘッダー (`Cache-Control "no-cache, no-store, must-revalidate"`)。
  - CORS ヘッダー (`Access-Control-Allow-Origin "*"`)。
  - MIME タイプ（HTML, JSON, Markdown text/plain, CSS, JS）を定義。
- **Docker Compose (`docker-compose.yml`)**:
  - `ingress-proxy` サービスに `./logs/report:/usr/share/nginx/html/report:ro` をマウント。

### 機能 2: LLM エージェント監視用 API & Markdown 要約
- **構造化 JSON (`status.json`)**:
  - LLM が `curl` や `jq` で即座に状態判断できるよう、サマリー、LLM 使用量推計、事前計算アラート (`alerts` 配列)、大容量通信リスト、直近遮断一覧を提供。
- **Markdown 要約 (`summary.md`)**:
  - わずか 200〜400 トークン程度で全体の健全度（✅ 正常 / ⚠️ 警告 / 🚨 異常）、主要ドメイン、アラート、プロバイダー別コストを俯瞰可能。

### 機能 3: LLM API 使用量・コスト・トークンのメタデータ推計
- **単価・閾値外部化 (`config/llm-pricing.json`)**:
  - プロバイダーごとの 1M トークン単価（ドル換算）、為替レート (`usd_to_jpy`)、アラート閾値を分離。
- **推計アルゴリズム**:
  - TLS 終端なしの前提を踏まえ、オーダー推定（概算 ±50%）としてラベリング。
  - 1リクエストあたりのプロトコルオーバーヘッド（約 500〜800 bytes）を減算補正。

---

## 3. 変更・追加ファイル一覧

| 対象ファイル | 区分 | 主な変更内容 |
|:---|:---:|:---|
| `nginx/nginx.conf` | 修正 | `location /report/` の追加、MIME タイプ、CORS、キャッシュ無効化ヘッダー |
| `docker-compose.yml` | 修正 | `ingress-proxy` サービスに `./logs/report:/usr/share/nginx/html/report:ro` をマウント |
| `config/llm-pricing.json` | 新規 | プロバイダー別トークン単価設定およびアラート閾値定義 |
| `bin/generate-report.sh` | 修正 | `uv run python` による HTML / JSON / Markdown 一括生成スクリプト |
| `Makefile` | 修正 | `report`, `report-json`, `report-watch` ターゲットの追加・拡充 |
| `README.md` | 修正 | Web ダッシュボードおよび LLM 向け API の利用手順を明記 |
| `plan/observability_enhancement_plan.md` | 修正 | 実装完了内容とデュアルインターフェース設計の反映 |
