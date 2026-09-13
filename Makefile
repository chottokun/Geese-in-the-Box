.PHONY: build up-proxy down test session serve gui logs audit-denied audit-summary clean help

# ==========================================
# Goose-in-the-Box (Docker 隔離 & 通信制御)
# ==========================================

# コンテナイメージのビルド
build:
	docker compose build

# プロキシコンテナの起動（バックグラウンド）
up-proxy:
	docker compose up -d egress-proxy

# 全コンテナの停止
down:
	docker compose down

# 通信遮断テストの実行 (L3/L4 内部隔離 & L7 Squid 制御)
test: up-proxy
	docker compose run --rm goose-agent /bin/test-egress.sh

# Goose CLI 対話セッションの起動 (AGENTS.md / ルール自動読み込み)
session: up-proxy
	docker compose run --rm goose-agent /bin/start-goose.sh

# Goose Desktop 向け ACP サーバー起動 (ポート 3284)
serve: up-proxy
	docker compose run --rm -p 127.0.0.1:3284:3284 goose-agent goose serve --host 0.0.0.0 --port 3284

# GUI デスクトップ環境の起動 (Xfce4 + noVNC: http://localhost:6080/vnc.html)
gui: up-proxy
	@echo "=========================================================="
	@echo " GUI デスクトップコンテナを起動しています..."
	@echo " 起動後、ブラウザで以下を開いてください:"
	@echo " 👉 http://localhost:6080/vnc.html"
	@echo " (または VNC クライアントで localhost:5900 に接続)"
	@echo "=========================================================="
	docker compose run --rm -p 127.0.0.1:6080:6080 -p 127.0.0.1:5900:5900 goose-agent /bin/start-desktop.sh

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

# クリーンアップ
clean:
	git clean -fdX workspace/
