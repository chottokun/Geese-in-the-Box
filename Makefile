.PHONY: build up-proxy down test test-unit session serve gui logs reload block-all unblock audit-denied audit-summary export-workspace clean help watch watch-webhook log-rotate audit-ingress report report-json report-watch audit-history control build-opencode run-opencode run-opencode-gui

# ==========================================
# Goose-in-the-Box (Docker 隔離 & 通信制御)
# ==========================================

# コンテナイメージのビルド
build:
	docker compose build

# プロキシコンテナ・コントロールパネル・Dozzleおよび監視自動集計の起動（バックグラウンド）
up-proxy:
	docker compose up -d egress-proxy ingress-proxy report-watcher control-panel dozzle

# 統合コントロールパネル Web UI (http://localhost:6080/control/)
control: up-proxy
	@echo "=========================================================="
	@echo " 🎛️ Goose-in-the-Box 統合コントロールパネル"
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
	docker compose down

# 通信遮断テストの実行 (L3/L4 内部隔離 & L7 Squid 制御)
test: up-proxy
	docker compose run --rm goose-agent /bin/test-egress.sh
	@echo "=== [監査ログ構造検証 (ホスト側)] ==="
	@docker compose exec -T egress-proxy cat /var/log/squid/access.json 2>/dev/null | tail -n 20 | grep -q "user_agent" && echo "  -> OK: 監査ログの JSON 構造 (user_agent 等) が正常に記録されています" || (echo "  -> FAIL: 監査ログに user_agent フィールドが見つかりません" && exit 1)


# Goose CLI 対話セッションの起動 (AGENTS.md / ルール自動読み込み)
session: up-proxy
	docker compose run --rm goose-agent /bin/start-goose.sh

# OpenCode コンテナのビルド
build-opencode:
	docker compose --profile opencode build opencode

# OpenCode 対話セッションの起動 (TUI モード)
run-opencode: up-proxy
	docker compose --profile opencode run --rm opencode opencode

# OpenCode GUI デスクトップ環境の起動 (Xfce4 + noVNC: http://localhost:6081/vnc.html)
run-opencode-gui: up-proxy
	@echo "=========================================================="
	@echo " OpenCode GUI デスクトップ環境を起動しています..."
	@echo " 起動後、ブラウザで以下を開いてください:"
	@echo " 👉 http://localhost:6081/vnc.html"
	@echo "=========================================================="
	docker compose --profile opencode run --rm --service-ports opencode /bin/start-opencode-desktop.sh

# Goose Desktop 向け ACP サーバー起動 (ポート 3284)
serve: up-proxy
	docker compose run --rm -p 127.0.0.1:3284:3284 goose-agent goose serve --host 0.0.0.0 --port 3284

# GUI デスクトップ環境の起動 (Xfce4 + noVNC: http://localhost:6080/vnc.html)
gui:
	@echo "=========================================================="
	@echo " GUI デスクトップ環境を起動しています..."
	@echo " 起動後、ブラウザで以下を開いてください:"
	@echo " 👉 http://localhost:6080/vnc.html"
	@echo "=========================================================="
	docker compose up -d

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
