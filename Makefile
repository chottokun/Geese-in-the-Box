.PHONY: build rebuild recreate clean-all up-proxy down test test-unit session serve gui logs reload block-all unblock audit-denied audit-summary export-workspace clean help watch watch-webhook log-rotate audit-ingress report report-json report-watch audit-history control build-opencode run-opencode run-opencode-gui build-openclaw run-openclaw run-openclaw-gui stop-openclaw stop-openclaw-gui


# ==========================================
# Geese-in-the-Box (Docker 隔離 & 通信制御)
# ==========================================

-include .env

# GPU 利用オプション (USE_GPU=1 または .env の USE_GPU=true で GPU を有効化、デフォルトは CPU のみ)
USE_GPU ?= 0
ifeq ($(filter 1 true TRUE,$(USE_GPU)),)
	COMPOSE_FILES := -f docker-compose.yml
else
	COMPOSE_FILES := -f docker-compose.yml -f docker-compose.gpu.yml
endif
DOCKER_COMPOSE := docker compose $(COMPOSE_FILES)

# コンテナ終了時の自動破棄フラグ (デフォルト: RM=1 で --rm を付与。RM=0 でコンテナを残して継続可能)
RM ?= 1
ifeq ($(filter 0 false FALSE,$(RM)),)
	RM_FLAG := --rm
else
	RM_FLAG :=
endif

# ヘルプ一覧の表示
help:
	@echo "=========================================================="
	@echo " Geese-in-the-Box 使い方"
	@echo "=========================================================="
	@echo " [初期設定・基本操作]"
	@echo "   make build           : コンテナイメージのビルド"
	@echo "   make rebuild         : キャッシュなしでイメージを完全再ビルド"
	@echo "   make recreate        : コンテナを破棄してイメージから強制再作成・再起動"
	@echo "   make down            : 全コンテナの停止・破棄"
	@echo "   make clean-all       : 全コンテナ・孤立コンテナ・全ボリュームの完全破棄"
	@echo "   make test            : 通信遮断テストの実行"
	@echo "   make control         : 統合コントロールパネルの起動 (http://localhost:6080/control/)"
	@echo ""
	@echo " [実行オプション]"
	@echo "   USE_GPU=1 make <cmd> : NVIDIA GPU パススルーを有効化 (例: USE_GPU=1 make session)"
	@echo "   RM=0 make <cmd>      : コンテナ終了時に破棄せず保持 (次回変更を継続可能, デフォルト: RM=1 で --rm)"
	@echo ""
	@echo " [Goose 操作]"
	@echo "   make session         : Goose CLI 対話セッションの起動 (ターミナル)"
	@echo "   make gui             : Goose GUI デスクトップ環境の起動 (http://localhost:6080/vnc.html)"
	@echo "   make serve           : Goose Desktop 向け ACP サーバー起動"
	@echo ""
	@echo " [OpenCode 操作]"
	@echo "   make build-opencode  : OpenCode コンテナのビルド"
	@echo "   make run-opencode    : OpenCode 対話セッションの起動 (ターミナル)"
	@echo "   make run-opencode-gui: OpenCode GUI デスクトップ環境の起動 (http://localhost:6081/vnc.html)"
	@echo ""
	@echo " [OpenClaw 操作]"
	@echo "   make build-openclaw  : OpenClaw コンテナのビルド"
	@echo "   make run-openclaw    : OpenClaw 対話セッションの起動 (ターミナル)"
	@echo "   make run-openclaw-gui: OpenClaw GUI デスクトップ環境の起動 (http://localhost:6082/vnc.html)"
	@echo "   make stop-openclaw   : OpenClaw コンテナの停止"
	@echo "=========================================================="

# コンテナイメージのビルド
build:
	$(DOCKER_COMPOSE) build

# キャッシュなし完全再ビルド
rebuild:
	$(DOCKER_COMPOSE) build --no-cache

# コンテナの破棄と強制再作成・再起動
recreate: down
	$(DOCKER_COMPOSE) up -d --force-recreate

# コンテナ・孤立コンテナ・全ボリュームの完全破棄（初期化）
clean-all:
	$(DOCKER_COMPOSE) down -v --remove-orphans
	@echo "全コンテナとボリュームを完全に破棄・初期化しました。"

# プロキシコンテナ・コントロールパネル・Dozzleおよび監視自動集計の起動（バックグラウンド）
up-proxy:
	$(DOCKER_COMPOSE) up -d egress-proxy ingress-proxy report-watcher control-panel dozzle

# 統合コントロールパネル Web UI (http://localhost:6080/control/)
control: up-proxy
	@echo "=========================================================="
	@echo " 🎛️ Geese-in-the-Box 統合コントロールパネル"
	@echo " ブラウザで以下の URL を開いてください:"
	@echo " 👉 http://localhost:6080/control/"
	@echo "=========================================================="

# コントロールパネルのユニットテスト実行 (uv / pytest)
test-unit:
	uv run --with pytest --with pytest-asyncio --with httpx --with fastapi pytest tests/

# コードの静的解析 (uv / ruff)
lint:
	uv run --with ruff ruff check .

# 全コンテナの停止
down:
	$(DOCKER_COMPOSE) down

# 通信遮断テストの実行 (L3/L4 内部隔離 & L7 Squid 制御)
test: up-proxy
	$(DOCKER_COMPOSE) run $(RM_FLAG) goose-agent /bin/test-egress.sh
	@echo "=== [監査ログ構造検証 (ホスト側)] ==="
	@docker compose exec -T egress-proxy cat /var/log/squid/access.json 2>/dev/null | tail -n 20 | grep -q "user_agent" && echo "  -> OK: 監査ログの JSON 構造 (user_agent 等) が正常に記録されています" || (echo "  -> FAIL: 監査ログに user_agent フィールドが見つかりません" && exit 1)


# Goose CLI 対話セッションの起動 (AGENTS.md / ルール自動読み込み)
session: up-proxy
	$(DOCKER_COMPOSE) run $(RM_FLAG) goose-agent /bin/start-goose.sh

# OpenCode コンテナのビルド
build-opencode:
	$(DOCKER_COMPOSE) --profile opencode build opencode

# OpenCode 対話セッションの起動 (TUI モード)
run-opencode: up-proxy
	$(DOCKER_COMPOSE) --profile opencode run $(RM_FLAG) opencode opencode

# OpenCode GUI デスクトップ環境の起動 (Xfce4 + noVNC: http://localhost:6081/vnc.html)
run-opencode-gui: up-proxy
	@docker rm -f opencode-agent 2>/dev/null || true
	@echo "=========================================================="
	@echo " OpenCode GUI デスクトップ環境を起動しています..."
	@echo " 起動後、ブラウザで以下を開いてください:"
	@echo " 👉 http://localhost:6081/vnc.html"
	@echo "=========================================================="
	$(DOCKER_COMPOSE) --profile opencode run $(RM_FLAG) --name opencode-agent opencode /bin/start-opencode-desktop.sh

# OpenClaw コンテナのビルド
build-openclaw:
	$(DOCKER_COMPOSE) --profile openclaw build openclaw

# OpenClaw 対話セッションの起動 (TUI モード)
run-openclaw: up-proxy
	$(DOCKER_COMPOSE) --profile openclaw run $(RM_FLAG) openclaw openclaw tui

# OpenClaw GUI デスクトップ環境の起動
run-openclaw-gui: up-proxy
	@echo "=========================================================="
	@echo " OpenClaw GUI デスクトップ環境を起動しています..."
	@echo " 起動後、ブラウザで以下を開いてください:"
	@echo " 👉 noVNC 起動 (ポート 6082)"
	@echo " 👉 OpenClaw UI 起動 (ポート 18789)"
	@echo "=========================================================="
	$(DOCKER_COMPOSE) --profile openclaw run $(RM_FLAG) --name openclaw-agent openclaw /bin/start-openclaw-desktop.sh

# OpenClaw コンテナの停止
stop-openclaw stop-openclaw-gui:
	$(DOCKER_COMPOSE) --profile openclaw stop openclaw
	@docker rm -f openclaw-agent 2>/dev/null || true


# Goose Desktop 向け ACP サーバー起動 (ポート 3284)
serve: up-proxy
	$(DOCKER_COMPOSE) run $(RM_FLAG) -p 127.0.0.1:3284:3284 goose-agent goose serve --host 0.0.0.0 --port 3284

# GUI デスクトップ環境の起動 (Xfce4 + noVNC: http://localhost:6080/vnc.html)
gui:
	@echo "=========================================================="
	@echo " GUI デスクトップ環境を起動しています..."
	@echo " 起動後、ブラウザで以下を開いてください:"
	@echo " 👉 http://localhost:6080/vnc.html"
	@echo "=========================================================="
	$(DOCKER_COMPOSE) up -d

# ==========================================
# 監査ログ・モニタリング
# ==========================================

# JSON 構造化監査ログのリアルタイム表示
logs:
	docker compose exec egress-proxy tail -f /var/log/squid/access.json

# 遮断された通信 (DENIED) のみ一覧表示
audit-denied:
	@docker compose exec -T egress-proxy cat /var/log/squid/access.json 2>/dev/null | jq -r 'select(.squid_status | test("DENIED")) | [.time, .client, .method, .domain, .url] | @tsv' || echo "ログがまだありません"

# 宛先ドメイン別アクセス集計トップ10
audit-summary:
	@./bin/audit-tools.sh domains

# 不正・拒否通信サマリー
audit-violations:
	@./bin/audit-tools.sh violations

# リアルタイムアラート監視の起動
watch:
	@./bin/watch-alerts.sh

# Webhook 付きアラート監視（環境変数 ALERT_WEBHOOK_URL を設定）
watch-webhook:
	@ALERT_WEBHOOK_URL=$(ALERT_WEBHOOK_URL) ./bin/watch-alerts.sh

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

# Ingress 接続履歴の表示
audit-ingress:
	@cat logs/nginx/ingress.json 2>/dev/null | jq -r '[.time, .remote_addr, .method, .uri, .status, .user_agent] | @tsv' | tail -20 || echo "ログがまだありません"

# HTML / JSON / Markdown 監査レポートの一括生成
report:
	@mkdir -p logs/report/api
	@chmod -R a+r logs/ 2>/dev/null || sudo chmod -R a+r logs/ 2>/dev/null || true
	@./bin/generate-report.sh
	@echo "📊 ダッシュボードを生成しました:"
	@echo "   - Web UI:   http://localhost:6080/report/"
	@echo "   - JSON API: logs/report/api/status.json"
	@echo "   - Markdown: logs/report/api/summary.md"

# LLM 向け JSON レポートのみ stdout に出力 (LLMエージェント監視パイプライン用)
report-json:
	@mkdir -p logs/report/api
	@chmod -R a+r logs/ 2>/dev/null || sudo chmod -R a+r logs/ 2>/dev/null || true
	@./bin/generate-report.sh >/dev/null 2>&1
	@cat logs/report/api/status.json

# レポートの自動更新ループ (30秒間隔でバックグラウンドまたはフォアグラウンド実行)
report-watch:
	@echo "レポートの自動更新ループを開始します (30秒間隔 / Ctrl+C で停止)..."
	@while true; do \
		./bin/generate-report.sh >/dev/null 2>&1; \
		echo "$$(date '+%Y-%m-%d %H:%M:%S') - レポートを更新しました"; \
		sleep 30; \
	done

# セッション横断の通信サマリー
audit-history:
	@./bin/session-audit.sh

# ==========================================
# 宛先ドメイン制御 & キルスイッチ
# ==========================================

# ホワイトリストの設定再読み込み（動的反映）
reload:
	docker compose exec egress-proxy squid -k reconfigure

# 緊急キルスイッチ（全拒否 ACL に切り替えて reconfigure）
block-all:
	@if [ ! -f squid/.whitelist.txt.bak ]; then \
		cp squid/whitelist.txt squid/.whitelist.txt.bak; \
	fi
	@echo "# ALL BLOCKED" > squid/whitelist.txt
	@echo "全通信を緊急遮断しました (block-all)"
	@$(MAKE) reload

# キルスイッチ解除（ホワイトリストを復元して reconfigure）
unblock:
	@if [ -f squid/.whitelist.txt.bak ]; then \
		mv squid/.whitelist.txt.bak squid/whitelist.txt; \
		echo "通信遮断を解除しました (unblock)"; \
		$(MAKE) reload; \
	else \
		echo "バックアップファイル (squid/.whitelist.txt.bak) が見つかりません"; \
	fi

# ワークスペース成果物のアーカイブ出力
export-workspace:
	@mkdir -p ./exports
	@FILENAME="exports/workspace_$$(date +%Y%m%d_%H%M%S).tar.gz"; \
	tar -czf "$$FILENAME" -C ./workspace . && \
	echo "成果物をアーカイブしました: $$FILENAME"

# クリーンアップ
clean:
	git clean -fdX workspace/
