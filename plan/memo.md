# 【実装・保守担当向け】Goose-in-the-Box 実装仕様・要件メモ

Goose-in-the-Box の設定ファイル、ネットワーク境界、運用スクリプトの仕様および保守ガイドです。

---

## 1. 主要ファイルと責務

### (1) `squid/squid.conf` & `squid/whitelist.txt`
- **責務**: L7 外部通信の監査・遮断。
- **仕様**:
  - `acl allowed_domains dstdomain "/etc/squid/whitelist.txt"` でドメイン制御。
  - Safe_ports に 11434 (Ollama) を許可。
  - 構造化 JSON ログフォーマット（`logformat json_custom ...`）で `/var/log/squid/access.json` に出力。
  - `make reload`（`squid -k reconfigure`）で動的反映。

### (2) `nginx/nginx.conf`
- **責務**: Ingress リバースプロキシ（外部からの WebSocket / HTTP 受信）。
- **仕様**:
  - ポート 6080（noVNC）および 3284（Goose ACP）を転送。
  - `proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "Upgrade";` で WebSocket 完全対応。
  - `resolver 127.0.0.11 valid=5s;` で Docker 内部 DNS による動的 upstream 解決（コンテナ起動順序に依存しない耐障害性）。

### (3) `goose/Dockerfile`
- **責務**: エージェント作業コンテナ環境の定義。
- **仕様**:
  - `ghcr.io/astral-sh/uv:latest` より `uv`, `uvx` をマルチステージコピー。
  - Debian bookworm-slim ベース。
  - `python3-pip`, `python3-venv`, `pipx`, `nodejs`, `npm`, `tmux`, `build-essential` を導入。
  - 公式 Goose Desktop 1.50.0 (`.deb`) を導入し、`/usr/lib/goose/Goose` を `--no-sandbox` ラッパーに置換。
  - `/usr/local/bin/goose` を純粋な CLI バイナリ（`/usr/lib/goose/resources/bin/goose`）へリンク。
  - Fcitx5 + Mozc 日本語入力設定、Git 自動設定（`user.name`, `user.email`, `safe.directory`）。

### (4) `docker-compose.yml`
- **責務**: コンテナ構成・ネットワーク・永続化ボリュームの結合。
- **仕様**:
  - `internal-net`: `internal: true` により外部通信が一切不可。
  - `external-net`: プロキシのみが所属。
  - 環境変数: `GOOSE_DISABLE_KEYRING=1`, `CONTEXT_FILE_NAMES=.goosehints,AGENTS.md`
  - ボリュームマウント:
    - `./workspace:/workspace:rw` (作業コード)
    - `./config:/home/sandboxuser/.config/goose:rw` (設定)
    - `./data/sessions:/home/sandboxuser/.local/share/goose/sessions:rw` (セッションDB)
    - `./data/logs:/home/sandboxuser/.local/state/goose/logs:rw` (Gooseログ)

---

## 2. 運用・保守コマンド

```bash
# ビルド
make build

# 起動（全コンテナ）
make gui

# 通信遮断テスト
make test

# ログ監視
make logs              # CLI JSONログ
make audit-denied      # 403 遮断ログのみ抽出
make audit-summary     # ドメイン別集計

# キルスイッチ
make block-all         # 緊急全遮断
make unblock           # 遮断解除

# 成果物エクスポート
make export-workspace  # exports/ 配下に日付付き tar.gz を出力
```