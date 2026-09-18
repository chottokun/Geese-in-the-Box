# Goose-in-the-Box: コンテナ通信制御＆監査サンドボックス 実装計画書 (v4)

> **基本方針**:
> ハイパーバイザー型 VM（Multipass 等）のような重厚な仮想化レイヤーは不要とし、**Docker コンテナ基盤** を採用する。
> Docker の `internal: true` ネットワーク（L3/L4）と、Squid フォワードプロキシ（L7）の **多層防御** により、AI エージェントの未許可の外部通信を遮断し、全通信を構造化 JSON ログに記録・監査する。
> さらに、**公式 Goose Desktop GUI（noVNC ブラウザ提供）**、**日本語入力環境（Fcitx5+Mozc）**、**MCP/パッケージ実行基盤（uv/uvx, npm/npx, pipx）**、および **成果物エクスポート** を備えたスターター環境を提供する。

---

## 1. システムアーキテクチャ

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│  ホストマシン                                                                │
│                                                                             │
│  [ブラウザ (Web)] ─── HTTP (localhost:6080/vnc.html) ──────────┐            │
│  [Goose Desktop] ──── HTTP (localhost:3284) ────────────────────┤            │
│  [Webログ監視]   ──── HTTP (localhost:8080 Dozzle) ──┐          │            │
│  [監査CLI/集計]  ──── 監査ログ閲覧 (make audit-summary) ┼───────┼────────┐   │
│  [成果物共有]    ──── ./workspace (リアルタイム同期)  │       │        │   │
└───────────────────────────────────────────────────────┼───────┼────────┼───┘
                                                        │       │        │
                        ┌───────────────────────────────┼───────┼────────┼───┐
                        │ Docker 仮想ネットワーク境界   │       │        │   │
                        │                               ▼       │        │   │
                        │  ┌─────────────────────────────────┐  │        │   │
                        │  │ ingress-proxy (Nginx: 6080/3284)│  │        │   │
                        │  │  └─ WebSocket / noVNC / ACP 中継│  │        │   │
                        │  └────────────────┬────────────────┘  │        │   │
                        │                   │                   │        │   │
                        │  ┌────────────────▼────────────────┐  │        │   │
                        │  │ goose-agent コンテナ            │  │        │   │
                        │  │  ├─ Goose Desktop GUI (Electron)│  │        │   │
                        │  │  ├─ Goose CLI (純粋バイナリ)    │  │        │   │
                        │  │  ├─ Xfce4 + Xvfb + noVNC        │  │        │   │
                        │  │  ├─ Fcitx5 + Mozc (日本語入力)  │  │        │   │
                        │  │  ├─ uv / uvx / pipx (Python MCP)│  │        │   │
                        │  │  ├─ node / npm / npx (Node MCP) │  │        │   │
                        │  │  ├─ tmux (セッション/プロセス)  │  │        │   │
                        │  │  ├─ git (自動初期設定済み)      │  │        │   │
                        │  │  ├─ .goosehints / AGENTS.md     │  │        │   │
                        │  │  └─ HTTP_PROXY=egress-proxy:3128│  │        │   │
                        │  └────────────────┬────────────────┘  │        │   │
                        │                   │                   │        │   │
                        │  ═════════════════▼═════════════════  │        │   │
                        │   internal-net (bridge, internal:true)│        │   │
                        │   ※ 外部ゲートウェイなし。直接通信は │        │   │
                        │      カーネルが「Network unreachable」│        │   │
                        │  ═════════════════╤═════════════════  │        │   │
                        │                   │                   │        │   │
                        │  ┌────────────────▼────────────────┐  │        │   │
                        │  │ egress-proxy コンテナ (Squid)   │  │        │   │
                        │  │  ├─ ドメインホワイトリスト判定  │  │        │   │
                        │  │  │  (whitelist.txt 以外は 403)  │  │        │   │
                        │  │  ├─ JSON 構造化監査ログ         │──┴────────┼───┘
                        │  │  └─ ポート 3128 リスニング      │           │
                        │  └────────────────┬────────────────┘           │
                        │                   │                            │
                        │  ┌────────────────▼────────────────┐           │
                        │  │ dozzle (Web ログビューワー:8080)│───────────┘
                        │  └─────────────────────────────────┘
                        │                   │
                        │  ═════════════════╪═════════════════
                        │   external-net (bridge)
                        │  ═════════════════╪═════════════════
                        └───────────────────┼─────────────────
                                            ▼
                               インターネット (LLM API, PyPI, npm, GitHub)
```

---

## 2. 実装されたコンポーネント詳細

### (1) Egress Control Proxy (Squid)
- **設定ファイル**: `squid/squid.conf`, `squid/whitelist.txt`
- **機能**:
  - `whitelist.txt` 記載ドメインのみ `CONNECT / GET` を許可、未登録は `403 Forbidden`。
  - Safe_ports に 11434 (Ollama) を許可。
  - パッケージリポジトリ（`pypi.org`, `files.pythonhosted.org`, `registry.npmjs.org`）の通信を許可。
  - ISO8601 タイムスタンプ付き構造化 JSON ログ（`/var/log/squid/access.json`）を常時出力。
  - `make reload` による動的設定反映、`make block-all` / `make unblock` による緊急キルスイッチ。

### (2) Ingress Reverse Proxy (Nginx)
- **設定ファイル**: `nginx/nginx.conf`
- **ポート**: `6080` (noVNC), `3284` (Goose ACP)
- **機能**:
  - WebSocket（`Upgrade`, `Connection "Upgrade"`）をサポート。
  - Docker 内部 DNS（`resolver 127.0.0.11`）による動的 upstream 解決（起動順序依存クラッシュの回避）。

### (3) Goose Agent Container (隔離作業環境)
- **Dockerfile**: `goose/Dockerfile`
- **機能**:
  - **公式 Goose Desktop 1.50.0**: `--no-sandbox` & Ozone IME ラッパー経由で Xfce4 デスクトップ上に起動。
  - **純粋 CLI バイナリ**: `/usr/local/bin/goose` を resources 配下の純粋バイナリに紐付け、ターミナルからの `goose session` を安定実行。
  - **日本語環境**: `C.UTF-8` ロケール、Noto CJK フォント、Fcitx5 + Mozc 日本語入力。
  - **MCP・開発ランタイム**:
    - `uv` / `uvx` (0.12.13): Astral 公式マルチステージコピーによる決定論的ビルド。
    - `pipx` (1.1.0): 独立仮想環境での Python ツール実行。
    - `python3-pip`, `python3-venv`, `nodejs`, `npm`, `npx`
    - `tmux 3.3a`: マウス有効化、セッション・常駐サーバー管理。
    - `build-essential`, `wget`, `unzip`, `patch`, `nano`, `less`, `htop`, `tree`
  - **Git 初期設定**: `user.name`, `user.email`, `safe.directory /workspace`, `init.defaultBranch main`。
  - **公式ヒント & 秘密情報**:
    - `/workspace/.goosehints`（プロジェクト指示書）
    - `CONTEXT_FILE_NAMES=.goosehints,AGENTS.md`
    - `GOOSE_DISABLE_KEYRING=1`（Keyring エラー回避）
  - **データ永続化**:
    - `./workspace:/workspace:rw`（コードのリアルタイム同期）
    - `./config:/home/sandboxuser/.config/goose:rw`（設定永続化）
    - `./data/sessions:/home/sandboxuser/.local/share/goose/sessions:rw`（セッションDB）
    - `./data/logs:/home/sandboxuser/.local/state/goose/logs:rw`（ログ）

### (4) 成果物エクスポート
- `make export-workspace` により、`./workspace` の最新成果物を日付付きアーカイブ（`exports/workspace_YYYYMMDD_HHMMSS.tar.gz`）としてワンライナーで出力。

---

## 3. 受入基準と検証結果

| # | 検証項目 | 検証コマンド / 操作 | 結果 |
|---|---|---|---|
| 1 | ホワイトリスト通信許可 | `test-egress.sh` (api.openai.com) | ✅ PASS (200 OK) |
| 2 | 未許可ドメイン遮断 | `test-egress.sh` (google.com) | ✅ PASS (403 Forbidden) |
| 3 | プロキシバイパス遮断 | `test-egress.sh` (直接IP/ドメイン宛) | ✅ PASS (Network unreachable) |
| 4 | パッケージ取得疎通 | `npm ping` / `curl -sI https://pypi.org/simple/` | ✅ PASS (Squid 経由で疎通) |
| 5 | 言語ランタイム & MCP | `uv`, `uvx`, `pipx`, `npm`, `npx`, `python3` | ✅ PASS (全コマンド正常) |
| 6 | Git 自動設定 | `git config -l` | ✅ PASS (user.name/email/safe.dir) |
| 7 | セッション永続化 (tmux) | `tmux new-session -d` / `tmux ls` | ✅ PASS |
| 8 | GUI デスクトップ & IME | ブラウザで `http://localhost:6080/vnc.html` | ✅ PASS (Xfce4 + Mozc + Goose GUI) |
| 9 | 成果物アーカイブ | `make export-workspace` | ✅ PASS (tar.gz 出力) |
