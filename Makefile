.PHONY: build up-proxy test session logs clean

# コンテナイメージのビルド
build:
	docker compose build

# プロキシのみをバックグラウンド起動
up-proxy:
	docker compose up -d egress-proxy

# 通信遮断テストの実行（プロキシ起動を前提条件にする）
test: up-proxy
	docker compose run --rm goose-agent /bin/test-egress.sh

# Gooseセッションの開始（プロキシ起動を前提条件にする）
session: up-proxy
	docker compose run --rm goose-agent

# プロキシのアクセスログをリアルタイム表示
logs:
	docker exec -it $$(docker compose ps -q egress-proxy) tail -f /var/log/squid/access.log

# ワークスペースと設定の生成物をクリーンアップ
clean:
	git clean -fdX workspace/ config/
