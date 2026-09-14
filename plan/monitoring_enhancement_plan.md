# 通信監視機能強化 実装計画書 (v5)

> **基本方針**:
> 本プロジェクトは **AIエージェントの実行環境** が主目的であり、通信監視はその安全運用を支える補助機能である。
> エージェントの生産性を阻害する過度な隔離（SSL Bump によるTLS復号、syscall トレーシング等）は採用せず、
> **既存アーキテクチャの延長線上で費用対効果の高い改善** を段階的に実施する。

---

## 設計原則

1. **エージェントの生産性を最優先**: MCP サーバー追加、パッケージインストール等の開発体験を妨げない
2. **既存構成への最小侵襲**: 新コンテナの追加は最小限にし、既存設定ファイルの拡張で対応する
3. **監視は "見える化" に集中**: ペイロード復号のような侵入的手法ではなく、メタデータの充実とアラートで実用的な可観測性を確保する
4. **段階的導入**: フェーズごとに独立してデプロイ・検証可能にし、一括導入のリスクを回避する

---

## フェーズ構成と全体ロードマップ

```text
フェーズ1 (即時対応)        フェーズ2 (監視基盤)           フェーズ3 (分析・運用)
━━━━━━━━━━━━━━━━━━━━    ━━━━━━━━━━━━━━━━━━━━━━━━    ━━━━━━━━━━━━━━━━━━━━━━━━
 監査ログの情報量強化        リアルタイムアラート           ダッシュボード
 環境変数の安全な注入        ログローテーション             セッション横断分析
 Ingress ログの追加          テストスイートの拡充           運用ドキュメント整備
 Squid ACL の精緻化          Makefile 統合
```

---

## フェーズ1: 監査ログの品質向上と基本的な安全強化

> **目標**: 既存ファイルの数行変更で、監視の情報量と基本的な安全性を大幅に向上させる
> **想定工数**: 1〜2時間
> **影響範囲**: `squid/squid.conf`, `nginx/nginx.conf`, `docker-compose.yml`

---

### 1.1 監査ログフィールドの拡充

**対象ファイル**: `squid/squid.conf`

**現状の問題**:
現在の `logformat json_audit` にはドメイン・バイト数・ステータスしか記録されておらず、
「どのツール/ライブラリが通信を発生させたか」「何のコンテンツタイプか」が不明。

**変更内容**:

```diff
 # 全通信（許可・遮断とも）を JSON 形式で詳細に記録
-logformat json_audit {"time":"%{%Y-%m-%dT%H:%M:%S%z}tl","client":"%>a","status":%>Hs,"squid_status":"%Ss","method":"%rm","url":"%ru","domain":"%>rd","bytes_sent":%<st,"bytes_received":%>est,"duration_ms":%tr}
+logformat json_audit {"time":"%{%Y-%m-%dT%H:%M:%S%z}tl","client":"%>a","status":%>Hs,"squid_status":"%Ss","method":"%rm","url":"%ru","domain":"%>rd","bytes_sent":%<st,"bytes_received":%>est,"duration_ms":%tr,"user_agent":"%{User-Agent}>h","content_type":"%{Content-Type}>h","referer":"%{Referer}>h"}
 access_log /var/log/squid/access.json json_audit
```

**追加フィールド**:

| フィールド | 値の例 | 監視上の意義 |
|:-----------|:-------|:-------------|
| `user_agent` | `python-requests/2.31.0`, `node-fetch/3.3` | どのツール/ライブラリが通信を発生させたかを特定 |
| `content_type` | `application/json`, `text/html` | 送受信データの種別を把握 |
| `referer` | URL or `-` | 通信の文脈（何をきっかけに発生したか）を推定 |

**注意事項**:
- HTTPS CONNECT メソッドでは `User-Agent` 等のヘッダーは取得できない場合がある（TLS トンネル内のため）。その場合 `-` が記録される。これは SSL Bump を行わない方針の範囲内で想定される制限であり、許容する
- HTTP 接続（ポート 80, 11434 等）では完全に記録される

---

### 1.2 Ingress 通信ログの追加

**対象ファイル**: `nginx/nginx.conf`

**現状の問題**:
Nginx にアクセスログ設定がなく、noVNC や ACP サーバーへの接続記録が一切残らない。
「いつ誰がエージェントのデスクトップに接続したか」が不可視。

**変更内容**:

```diff
 http {
     include       mime.types;
     default_type  application/octet-stream;
     sendfile        on;
     keepalive_timeout  65;

+    # Ingress 監査ログ（JSON 構造化）
+    log_format json_ingress escape=json
+        '{"time":"$time_iso8601",'
+        '"remote_addr":"$remote_addr",'
+        '"method":"$request_method",'
+        '"uri":"$request_uri",'
+        '"status":$status,'
+        '"bytes_sent":$bytes_sent,'
+        '"upstream":"$upstream_addr",'
+        '"user_agent":"$http_user_agent",'
+        '"connection_upgrade":"$http_upgrade"}';
+
+    access_log /var/log/nginx/ingress.json json_ingress;
+
     # Docker 組み込み DNS サーバー
     resolver 127.0.0.11 valid=5s ipv6=off;
```

**docker-compose.yml への追加**:

```diff
   ingress-proxy:
     image: nginx:alpine
     ...
     volumes:
       - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
+      - ./logs/nginx:/var/log/nginx
```

**ログ出力先**: `logs/nginx/ingress.json`（ホストから閲覧可能）

---

### 1.3 環境変数の選択的注入

**対象ファイル**: `docker-compose.yml`

**現状の問題**:
`env_file: - .env` で `.env` ファイル全体をエージェントコンテナに注入している。
使用しないプロバイダーのAPIキーも全てコンテナ環境変数に展開されるため、
エージェントが `env` コマンドや `/proc/self/environ` で読み取り可能。

**設計判断**:
エージェント実行環境としての利便性を考慮し、**使用するプロバイダーのキーのみ** を注入する方式に変更する。
ただし、複数プロバイダーを切り替える柔軟性も維持する。

**変更方針**:

```diff
   goose-agent:
     ...
-    env_file:
-      - .env
     environment:
       - HTTP_PROXY=http://egress-proxy:3128
       - HTTPS_PROXY=http://egress-proxy:3128
       ...
+      # --- LLM プロバイダー（使用するキーのみ選択的に注入） ---
+      - OLLAMA_HOST=${OLLAMA_HOST:-}
+      - OPENAI_API_KEY=${OPENAI_API_KEY:-}
+      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}
+      - GOOGLE_API_KEY=${GOOGLE_API_KEY:-}
+      - GOOSE_PROVIDER=${GOOSE_PROVIDER:-}
+      - GOOSE_MODEL=${GOOSE_MODEL:-}
```

**メリット**:
- `docker-compose.yml` に明示された変数のみがコンテナに入る（可視性の向上）
- `.env` に `SQUID_PORT` や `DOZZLE_PORT` のようなホスト側設定が漏洩しない
- 必要に応じて `environment:` セクションにキーを追加するだけで拡張可能

---

### 1.4 Squid ACL の精緻化（host.docker.internal ポート制限）

**対象ファイル**: `squid/squid.conf`

**現状の問題**:
`host.docker.internal` がドメインとして許可されているが、ポート制限がない。
ホスト上の任意のサービスにアクセス可能。

**変更内容**:

```diff
+# Ollama ローカル LLM 用ポート制限
+acl ollama_port port 11434
+acl ollama_host dstdomain host.docker.internal
+
 # アクセスルール
+http_access allow localnet ollama_host ollama_port
 http_access allow localnet allowed_domains
```

```diff
 # squid/whitelist.txt から以下を削除
-# --- ローカル LLM (Ollama 等) ---
-host.docker.internal
```

**効果**: `host.docker.internal` への通信はポート `11434` のみに限定される

---

### フェーズ1 検証項目

| # | 検証内容 | 検証方法 | 期待結果 |
|---|:---------|:---------|:---------|
| 1 | ログに `user_agent` フィールドが記録される | `make logs` で HTTP 接続を確認 | フィールドが存在し値が記録される |
| 2 | Nginx の ingress ログが出力される | `cat logs/nginx/ingress.json` | noVNC 接続時のログエントリ |
| 3 | エージェント内で不要な環境変数が見えない | コンテナ内で `env \| grep SQUID` | 結果が空 |
| 4 | Ollama 以外のポートで `host.docker.internal` に接続不可 | コンテナ内で `curl http://host.docker.internal:8080` | 403 Forbidden |
| 5 | Ollama 接続が正常に動作する | コンテナ内で `curl http://host.docker.internal:11434/api/tags` | 正常レスポンス |
| 6 | 既存の通信テストが全て PASS する | `make test` | 3/3 PASS |

---

## フェーズ2: リアルタイム監視とテスト強化

> **目標**: 管理者が積極的にログを見に行かなくても異常に気づける仕組みを構築する
> **想定工数**: 3〜5時間
> **影響範囲**: `bin/` に新規スクリプト追加、`Makefile` に新ターゲット追加、`docker-compose.yml` 微修正

---

### 2.1 リアルタイムアラートスクリプト

**新規ファイル**: `bin/watch-alerts.sh`

**設計**:
Squid の JSON ログを `tail -f` で監視し、DENIED 通信を検出したらターミナルに色付きアラートを出力する。
軽量な bash スクリプトで実装し、外部依存（Prometheus 等）を導入しない。

**機能要件**:

```text
1. DENIED 通信をリアルタイム検出し、色付きで即座に表示
2. 短時間に同一ドメインへの DENIED が連続した場合、集約表示（ストーム抑制）
3. オプションで Webhook URL を指定すると、通知を POST 送信（将来対応用のフック）
```

**Makefile 統合**:

```makefile
# リアルタイムアラート監視の起動
watch:
	@./bin/watch-alerts.sh

# Webhook 付きアラート監視（環境変数 ALERT_WEBHOOK_URL を設定）
watch-webhook:
	@ALERT_WEBHOOK_URL=$(ALERT_WEBHOOK_URL) ./bin/watch-alerts.sh
```

---

### 2.2 ログローテーションの導入

**新規ファイル**: `squid/logrotate.conf`

**設計**:
Squid コンテナ内で `logrotate` を使用するのではなく、ホスト側のログディレクトリ `logs/squid/` に対して
`make` ターゲットで手動ローテーションを提供する。

**方針**:
- Squid の `squid -k rotate` コマンドを利用してログを安全にローテーション
- 古いログは日付サフィックス付きで保持
- `make log-rotate` で明示的に実行（自動化はホスト側の cron に委ねる）

**Makefile 統合**:

```makefile
# 監査ログのローテーション（古いログを日付付きで保存）
log-rotate:
	@TIMESTAMP=$$(date +%Y%m%d_%H%M%S); \
	for f in logs/squid/access.json logs/squid/access.log; do \
		if [ -f "$$f" ]; then \
			cp "$$f" "$$f.$$TIMESTAMP"; \
			truncate -s 0 "$$f"; \
		fi; \
	done; \
	docker compose exec egress-proxy squid -k rotate 2>/dev/null || true; \
	echo "ログをローテーションしました ($$TIMESTAMP)"
```

---

### 2.3 テストスイートの拡充

**対象ファイル**: `bin/test-egress.sh` の拡張

**追加テスト項目**:

```text
[4/6] host.docker.internal ポート制限テスト
  → ポート 11434 への接続: 許可されること
  → ポート 8080 への接続: 403 で拒否されること

[5/6] 監査ログ記録の正確性テスト
  → テスト通信後にログファイルを読み取り、該当エントリが正しく記録されていることを検証

[6/6] キルスイッチ動作テスト
  → block-all 後にホワイトリストドメインが拒否されること
  → unblock 後に復旧すること
```

---

### 2.4 Nginx Ingress ログの監査ツール統合

**対象ファイル**: `bin/audit-tools.sh` への追加

**追加コマンド**:

```text
  ingress     Ingress（ホスト→コンテナ）の接続履歴を表示
```

**Makefile 統合**:

```makefile
# Ingress 接続履歴の表示
audit-ingress:
	@cat logs/nginx/ingress.json 2>/dev/null | jq -r '[.time, .remote_addr, .method, .uri, .status, .user_agent] | @tsv' | tail -20 || echo "ログがまだありません"
```

---

### フェーズ2 検証項目

| # | 検証内容 | 検証方法 | 期待結果 |
|---|:---------|:---------|:---------|
| 1 | DENIED 通信でアラートが表示される | `make watch` 起動中に非許可ドメインへ接続 | 色付きアラート出力 |
| 2 | ログローテーションが動作する | `make log-rotate` 実行 | 日付付きバックアップが作成される |
| 3 | 拡張テストが全て PASS する | `make test` | 6/6 PASS |
| 4 | Ingress 監査が動作する | `make audit-ingress` | noVNC 接続ログが表示される |

---

## フェーズ3: 分析ダッシュボードと運用成熟

> **目標**: 監査データの長期的な蓄積・可視化と、運用ドキュメントの整備
> **想定工数**: 5〜8時間
> **影響範囲**: 新規ファイル追加が主（既存への変更は最小限）

---

### 3.1 HTML 監査ダッシュボード

**新規ファイル**: `bin/generate-report.sh`

**設計**:
外部ツール（Grafana, ELK 等）に依存せず、`jq` + `awk` でログを集計し、
静的な HTML レポートを生成するシェルスクリプトを作成する。

**レポート内容**:

```text
1. サマリー: 総通信数、許可数、遮断数、監視期間
2. ドメイン別アクセスランキング（棒グラフ: インラインSVG）
3. 時間帯別通信量（折れ線グラフ: インラインSVG）
4. 遮断された通信の詳細一覧（テーブル）
5. User-Agent 別の通信内訳
```

**Makefile 統合**:

```makefile
# HTML 監査レポートの生成
report:
	@./bin/generate-report.sh > logs/audit-report.html
	@echo "監査レポートを生成しました: logs/audit-report.html"
```

**設計判断**:
Grafana / Loki / Prometheus の導入は「エージェント実行環境としての軽量性」に反するため、
シェルスクリプト + 静的 HTML で十分な可視化を実現する。

---

### 3.2 セッション横断の通信サマリー

**新規ファイル**: `bin/session-audit.sh`

**機能**:
ローテーションされた過去のログファイルも含めて横断分析し、
セッション（日付）ごとの通信傾向を比較表示する。

```text
$ make audit-history

=== セッション別通信サマリー ===
日付           許可    遮断    総バイト    トップドメイン
2026-09-12     142      3     2.1 MB      api.openai.com
2026-09-13     287      0     5.8 MB      api.anthropic.com
2026-09-14      53      7     0.4 MB      registry.npmjs.org
```

---

### 3.3 運用ドキュメントの整備

**対象ファイル**: `README.md` への追記、`plan/memo.md` の更新

**追記内容**:

```text
## 通信監視・監査ガイド

### 監査ログの読み方
- 各フィールドの意味と分析のヒント
- よくあるパターン（正常 / 異常の見分け方）

### アラート運用
- watch-alerts.sh の使い方
- 頻出する誤検知パターンと対処法

### トラブルシューティング
- ログが出力されない場合
- ローテーション後にログが消えた場合
- Squid のリロードが反映されない場合
```

---

### 3.4 Extension Manager の制御オプション化

**対象ファイル**: `config/config.yaml` のテンプレート化

**設計**:
Extension Manager を一律無効化するのではなく、`.env` の設定で有効/無効を切り替え可能にする。

```text
# .env に追加
# GOOSE_LOCKDOWN_MODE=false  # true にすると Extension Manager を無効化
```

**設計判断**:
エージェント実行環境として、MCPサーバーの動的追加はコア機能である。
ただし、厳格な監視が必要な場面ではロックダウンできるオプションを用意する。

---

### フェーズ3 検証項目

| # | 検証内容 | 検証方法 | 期待結果 |
|---|:---------|:---------|:---------|
| 1 | HTML レポートが正常に生成される | `make report` → ブラウザで開く | グラフ・テーブルが表示される |
| 2 | セッション横断分析が動作する | ログローテーション後に `make audit-history` | 複数セッションが比較表示される |
| 3 | README の監査ガイドが正確 | ドキュメント通りに操作 | 記載通りに動作する |

---

## 変更ファイル一覧

### 既存ファイルの変更

| ファイル | フェーズ | 変更内容 |
|:---------|:--------:|:---------|
| `squid/squid.conf` | 1 | ログフォーマットにフィールド追加、Ollama ポート ACL 追加 |
| `squid/whitelist.txt` | 1 | `host.docker.internal` の行を削除（ACL に移行） |
| `nginx/nginx.conf` | 1 | JSON アクセスログの追加 |
| `docker-compose.yml` | 1 | `env_file` 廃止、環境変数の明示的注入、Nginx ログボリューム追加 |
| `bin/test-egress.sh` | 2 | テストケース 3件追加（計6件） |
| `bin/audit-tools.sh` | 2 | `ingress` サブコマンド追加 |
| `Makefile` | 2,3 | `watch`, `log-rotate`, `audit-ingress`, `report`, `audit-history` 追加 |
| `README.md` | 3 | 監査ガイドセクション追記 |
| `.env.example` | 1 | `ALERT_WEBHOOK_URL` 追加 |

### 新規ファイル

| ファイル | フェーズ | 内容 |
|:---------|:--------:|:-----|
| `bin/watch-alerts.sh` | 2 | リアルタイムアラート監視スクリプト |
| `bin/generate-report.sh` | 3 | HTML 監査レポート生成スクリプト |
| `bin/session-audit.sh` | 3 | セッション横断分析スクリプト |

---

## 採用しない施策と理由

以下の施策は、エージェント実行環境としての利便性・軽量性を損なうため、本計画では採用しない。

| 施策 | 不採用理由 |
|:-----|:-----------|
| **SSL Bump (TLS 復号)** | エージェントの HTTPS 通信をすべて復号・再暗号化する。証明書ピンニングを行うライブラリ（一部の npm パッケージ等）が動作しなくなり、開発体験を著しく阻害する |
| **eBPF / auditd による syscall トレーシング** | コンテナに `CAP_SYS_ADMIN` 等の追加権限が必要。攻撃面を逆に拡大し、Dockerfile の複雑化も招く |
| **Grafana + Loki + Prometheus スタック** | 3つの追加コンテナが必要で、メモリ消費が大幅に増加。シェルスクリプトで十分な可視化が達成できる規模 |
| **DNS キャプチャサーバー (CoreDNS)** | `internal: true` ネットワーク内ではDNSによるデータ流出は原理的に不可能（外部DNSに到達できない）。Squid 経由の CONNECT で宛先ドメインは記録されるため、追加の DNS 監査は冗長 |
| **ログの暗号学的改ざん検知 (ハッシュチェーン)** | 個人利用の開発環境で改ざん耐性は過剰。ログの外部バックアップで十分 |
| **Extension Manager の強制無効化** | MCPサーバーの動的追加はGooseのコア機能であり、無効化はエージェントの実用価値を大きく損なう |

---

## 全体スケジュール

```text
フェーズ1 ─── 既存ファイルの修正のみで完結 ───── 1〜2時間
  ↓ make test で全検証 PASS を確認
フェーズ2 ─── 新規スクリプト + テスト拡張 ───── 3〜5時間
  ↓ make test + make watch で動作確認
フェーズ3 ─── レポート・ドキュメント整備 ───── 5〜8時間
  ↓ make report で最終確認
```

各フェーズは独立してデプロイ・検証可能。フェーズ1完了時点で実用上十分な改善が得られる。
