実装担当者（リポジトリの構築・CI整備・設定ファイルを実際にコーディング・保守するエンジニア）向けに、具体的な設定ファイルの内容と実装要件をまとめた仕様書です。

---

**【実装担当向け】Goose Egress サンドボックス 実装仕様・要件書**

**1. 実装チェックリスト**

* [ ] `squid.conf` を修正し、ホワイトリストを `whitelist.txt` 外部読み込みに変更
* [ ] `docker-compose.yml` に `egress-proxy` のヘルスチェックと依存関係（`depends_on`）を追加
* [ ] `./workspace` の UID/GID 権限問題を環境変数で吸収できる設計を導入
* [ ] `Makefile` の各ターゲットにプロキシ依存関係と `clean` 処理を追加
* [ ] GitHub Actions（`ci.yml`）で `make test` を自動実行するパイプラインを定義

---

**2. 主要ファイルの実装詳細**

**`squid/squid.conf` & `squid/whitelist.txt**`
外部ファイルからドメインを読み込む設定にします。

```text
# squid/squid.conf
acl allowed_domains dstdomain "/etc/squid/whitelist.txt"
http_access allow allowed_domains
http_access deny all
http_port 3128

```

```text
# squid/whitelist.txt
# サブドメイン全体を許可する場合は先頭にドット（例: .anthropic.com）
api.openai.com
.anthropic.com

```

---

**`docker-compose.yml`**
プロキシのヘルスチェック、依存関係、ユーザーIDの柔軟性、設定永続化マウントを定義します。

```yaml
services:
  egress-proxy:
    image: ubuntu/squid:latest
    volumes:
      - ./squid/squid.conf:/etc/squid/squid.conf:ro
      - ./squid/whitelist.txt:/etc/squid/whitelist.txt:ro
    networks:
      - sandbox-internal
      - public-egress
    healthcheck:
      test: ["CMD-SHELL", "nc -z 127.0.0.1 3128 || exit 1"]
      interval: 3s
      timeout: 3s
      retries: 5

  goose-agent:
    build:
      context: .
      dockerfile: goose/Dockerfile
    user: "${UID:-1000}:${GID:-1000}"
    environment:
      - HTTP_PROXY=http://egress-proxy:3128
      - HTTPS_PROXY=http://egress-proxy:3128
      - http_proxy=http://egress-proxy:3128
      - https_proxy=http://egress-proxy:3128
    env_file:
      - .env
    volumes:
      - ./workspace:/workspace:rw
      - ./config:/home/sandboxuser/.config/goose:rw
    working_dir: /workspace
    networks:
      - sandbox-internal
    depends_on:
      egress-proxy:
        condition: service_healthy

networks:
  sandbox-internal:
    internal: true   # ホスト外への直接ルーティングを遮断[cite: 2]
  public-egress:      # プロキシのみが外部と通信可能

```

---

**`Makefile`**
手動コマンドミスを防ぐため、プロキシ起動を前提条件にします。

```makefile
.PHONY: build up-proxy test session logs clean

build:
	docker compose build

up-proxy:
	docker compose up -d egress-proxy

test: up-proxy
	docker compose run --rm goose-agent /workspace/../bin/test-egress.sh

session: up-proxy
	docker compose run --rm goose-agent

logs:
	docker exec -it $$(docker compose ps -q egress-proxy) tail -f /var/log/squid/access.log

clean:
	git clean -fdX workspace/ config/

```

---

**`.github/workflows/ci.yml`**
PR作成時に設定が壊れていないか、遮断テストを自動実行します。

```yaml
name: CI Sandbox Egress Test

on:
  pull_request:
    paths:
      - 'squid/**'
      - 'goose/**'
      - 'docker-compose.yml'
      - 'bin/**'

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup environment
        run: |
          touch .env
          mkdir -p workspace config

      - name: Run Egress Test
        run: |
          make build
          make test

```