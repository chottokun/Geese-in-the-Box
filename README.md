# Goose Egress Sandbox Package

AIエージェント「Goose」を隔離環境で安全に実行するためのDockerサンドボックスパッケージです。
SquidフォワードプロキシとDockerの `internal: true` ネットワークを組み合わせ、許可したドメイン以外への通信をカーネル/プロキシの2段構えで遮断します。

## 含まれるファイル構成

```text
goose-egress-sandbox/
├── docker-compose.yml       # 内部・外部隔離ネットワークおよびコンテナ構成
├── .env.example             # APIキー設定テンプレート
├── squid/
│   └── squid.conf           # ドメインホワイトリスト設定
├── goose/
│   └── Dockerfile           # Goose CLI + 依存ツール導入
├── bin/
│   └── test-egress.sh       # 通信遮断検証スクリプト
└── workspace/               # Goose作業用ディレクトリ（ホストとバインドマウント）
```

## クイックスタート

### 1. 初期設定
```bash
cp .env.example .env
# 必要に応じて .env に APIキーを設定
```

### 2. コンテナのビルドとプロキシ起動
```bash
docker compose build
docker compose up -d egress-proxy
```

### 3. 通信遮断テストの実行
Gooseコンテナを起動し、内部から検証スクリプトを実行して正しくホワイトリスト制御されているか確認します。
```bash
docker compose run --rm goose-agent /workspace/../bin/test-egress.sh
```
* `api.openai.com` 等は `200` で通過
* `google.com` 等は `403 Forbidden` で遮断
* プロキシを経由しない直接通信は `Network unreachable` で遮断

### 4. Gooseセッションの開始
```bash
docker compose run --rm goose-agent
# コンテナ内シェルで実行:
goose configure
goose session
```

## プロキシログのリアルタイム監査
ホスト側からプロキシのアクセスログを監視できます：
```bash
docker exec -it egress-proxy tail -f /var/log/squid/access.log
```
