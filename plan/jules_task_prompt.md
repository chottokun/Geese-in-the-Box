# 依頼タスク: 通信監視機能強化の実装 (plan/monitoring_enhancement_plan.md)

リポジトリ内の `plan/monitoring_enhancement_plan.md` に定義された仕様に基づき、エージェントの生産性を損なわずに通信監視・監査機能を強化する実装とテストの作成を行ってください。
テスト駆動開発 (TDD) の方針に沿って、拡張された検証スクリプトを作成・更新し、実装が正常に機能することを担保してください。

## 実装要件

### 1. フェーズ1: 監査ログ品質向上と設定の精緻化
1. **`squid/squid.conf`**:
   - `logformat json_audit` に `user_agent` (`%{User-Agent}>h`), `content_type` (`%{Content-Type}>h`), `referer` (`%{Referer}>h`) を追加。
   - `host.docker.internal` をホワイトリストドメインから除外し、Ollama 用ポート 11434 のみに制限する ACL を定義:
     ```squid
     acl ollama_port port 11434
     acl ollama_host dstdomain host.docker.internal
     http_access allow localnet ollama_host ollama_port
     ```
2. **`squid/whitelist.txt`**:
   - `host.docker.internal` を削除（squid.conf 側の個別ポート制限 ACL に移行するため）。
3. **`nginx/nginx.conf`**:
   - Ingress 監査用 JSON ログフォーマット `json_ingress` を定義し、`/var/log/nginx/ingress.json` に記録。
4. **`docker-compose.yml`**:
   - `env_file: - .env` による全環境変数一括流し込みをやめ、`environment:` 節で使用する変数（LLM APIキー、Ollamaホスト等）を明示的に指定。
   - `ingress-proxy` に `./logs/nginx:/var/log/nginx` のマウントを追加。
5. **`.env.example`**:
   - `ALERT_WEBHOOK_URL` などの新規オプション例を反映。

### 2. フェーズ2: 監視基盤・テスト・運用の強化
1. **`bin/watch-alerts.sh` (新規作成)**:
   - `/var/log/squid/access.json` をリアルタイム監視し、`DENIED` 通信を即座にカラー表示するアラートスクリプト。
   - 同一ドメインへの連続遮断の集約や `ALERT_WEBHOOK_URL` があれば Webhook 送信フックも備える。実行権限を付与すること。
2. **`bin/test-egress.sh` (拡張 - TDD)**:
   - 既存の3テストに加え、以下を追加し 6 項目を自動テストできるようにする:
     - [4/6] `host.docker.internal` ポート 11434 は許可、他ポート（例: 8080）は拒否されることの検証
     - [5/6] 監査ログ (`/var/log/squid/access.json`) に `user_agent` フィールド等の JSON 構造が記録されることの検証
     - [6/6] プロキシキルスイッチまたは未許可ドメインの遮断ログ整合性検証
3. **`bin/audit-tools.sh`**:
   - `ingress` コマンドを追加し、`logs/nginx/ingress.json` の内容を jq で見やすく一覧表示できるようにする。
4. **`Makefile`**:
   - `watch`: `./bin/watch-alerts.sh` の実行
   - `log-rotate`: 日付サフィックス付きログ退避・切り詰めと `squid -k rotate` の実行
   - `audit-ingress`: Ingress ログの確認コマンド

### 3. フェーズ3: 分析レポート生成
1. **`bin/generate-report.sh` (新規作成)**:
   - `logs/squid/access.json` をパースし、サマリー（総通信、許可、遮断）、ドメイン別集計、User-Agent 内訳、遮断一覧を含む静的 HTML レポートを出力する軽量スクリプト。実行権限を付与すること。
2. **`Makefile`**:
   - `report`: `./bin/generate-report.sh > logs/audit-report.html`

## 制約事項・確認事項
- コード内のコメントや出力メッセージ、ドキュメントは日本語で記述すること。
- スクリプト作成時は `chmod +x` を忘れず設定すること。
- エージェント作業環境としての利便性を損なわないこと（SSL Bump や過度な特権要求コンテナは導入しない）。
- 各スクリプトの構文チェック (`bash -n`) をパスすること。
