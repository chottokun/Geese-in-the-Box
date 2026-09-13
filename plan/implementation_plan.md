# Goose-in-the-Box: コンテナ完全通信制御＆監査サンドボックス 実装計画書 (v3)

> **基本方針**:
> ハイパーバイザー型 VM（Multipass 等）のような重厚な仮想化レイヤーは不要とし、**Docker コンテナ基盤** を採用する。
> Docker の `internal: true` ネットワーク（L3/L4）と、Squid フォワードプロキシ（L7）の **2段構え** により、AI エージェントの勝手な外部通信を 100% 遮断し、全通信を構造化 JSON ログに記録・監査する。
>
> **達成する要件**:
> 1. **後方互換性は不要**: 古い構成や未整理のファイルは一掃する。
> 2. **完全な通信制御**: 許可したドメイン以外への外部通信は物理的・論理的に遮断（プロキシバイパスの完全排除）。
> 3. **監査ログの厳密な記録**: 許可・拒否を問わず、全接続試行を ISO8601 タイムスタンプ付きの構造化 JSON ログに出力。
> 4. **軽量・即時検証**: 手元の Docker 環境ですぐに実動テスト可能。

---

## 1. システムアーキテクチャ

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│  ホストマシン                                                                │
│                                                                             │
│  [Goose Desktop (GUI)] ─── HTTP (localhost:3284) ──┐                        │
│  [ブラウザ / 監査CLI]   ─── 監査ログ・集計 ───────────┼──────────────────┐   │
│                                                     │                  │   │
└─────────────────────────────────────────────────────┼──────────────────┼───┘
                                                      │                  │
                      ┌───────────────────────────────┼──────────────────┼───┐
                      │ Docker 仮想ネットワーク境界   │                  │   │
                      │                               │                  │   │
                      │  ┌────────────────────────────▼───────────────┐  │   │
                      │  │ goose-agent コンテナ                        │  │   │
                      │  │  ├─ Goose CLI / ACP serve (3284)           │  │   │
                      │  │  ├─ workspace/ (AGENTS.md, スキル, ルール) │  │   │
                      │  │  ├─ テレメトリ無効化 (TELEMETRY=false)     │  │   │
                      │  │  └─ HTTP_PROXY=http://egress-proxy:3128    │  │   │
                      │  └────────────────────┬───────────────────────┘  │   │
                      │                       │                          │   │
                      │                       ▼                          │   │
                      │  ══════════════════════════════════════════════  │   │
                      │   internal-net (bridge, internal: true)          │   │
                      │   ※ 外部ゲートウェイなし。直接パケット送信は     │   │
                      │      カーネルが「Network unreachable」で即破棄   │   │
                      │  ══════════════════════════════════════════════  │   │
                      │                       │                          │   │
                      │                       ▼                          │   │
                      │  ┌────────────────────────────────────────────┐  │   │
                      │  │ egress-proxy コンテナ (Squid 7.x)           │  │   │
                      │  │  ├─ ドメインホワイトリスト判定 (L7)         │  │   │
                      │  │  │  (whitelist.txt 以外は 403 Forbidden)   │  │   │
                      │  │  ├─ JSON 構造化監査ログ (/var/log/squid/)   │──┼───┘
                      │  │  └─ ポート 3128 リスニング                 │  │
                      │  └────────────────────┬───────────────────────┘  │
                      │                       │                          │
                      │  ═════════════════════╪════════════════════════  │
                      │   external-net (bridge)                          │
                      │  ═════════════════════╪════════════════════════  │
                      └───────────────────────┼──────────────────────────┘
                                              ▼
                                 インターネット (外部 LLM API 等)
```

### 通信制御の2段構え（多層防御）

| レイヤー | 制御手段 | 具体的な動作と効果 |
|---------|---------|-------------------|
| **L3 / L4 (ネットワーク層)** | Docker `internal: true` | コンテナに外部向けデフォルトゲートウェイが割り当てられない。エージェントがプロキシ設定を無視して直接外部通信を試みても、OS カーネルがパケットを即座に破棄（プロキシ迂回は物理的に不可能）。 |
| **L7 (アプリケーション層)** | Squid フォワードプロキシ | `whitelist.txt` に記載されたドメイン宛ての CONNECT / HTTP リクエストのみ通過を許可。未許可ドメインは `403 Forbidden` で遮断。 |
| **監査 (Audit)** | Squid JSON ロガー | 全てのリクエスト（通過・遮断・エラー）について、日時、クライアントIP、宛先ドメイン、メソッド、レスポンスコード、送受信バイト数を JSON 形式で `/var/log/squid/access.json` に記録。 |

---

## 2. ディレクトリ構成と成果物

```text
goose-in-the-box/
├── docker-compose.yml       # 内部隔離(internal-net)と外部プロキシ(external-net)の定義
├── Makefile                 # ビルド、テスト、セッション起動、監査集計ワンライナー
├── README.md                # セットアップ・テスト・監査手順の完全ガイド
├── .env.example             # LLMプロバイダー用APIキーテンプレート
├── squid/
│   ├── squid.conf           # 厳格なフォワードプロキシ設定 + JSON構造化監査ログ定義
│   └── whitelist.txt        # 許可ドメイン一覧（OpenAI, Anthropic, Gemini, GitHub等）
├── goose/
│   └── Dockerfile           # Goose CLI + 依存ツールを導入した軽量コンテナ
├── bin/
│   ├── test-egress.sh       # 通信遮断・プロキシ迂回防止・監査ログの自動検証スクリプト
│   └── start-goose.sh       # AGENTS.md / ルール自動結合とGoose対話セッション起動
├── workspace/               # Goose作業ディレクトリ（ホストとマウント）
│   ├── AGENTS.md            # 作業ルール・セキュリティガイドライン
│   └── .agents/             # スキルや分割ルールの配置場所
├── logs/                    # Squid 監査ログ出力先（ホストから閲覧可能）
│   └── squid/
│       ├── access.json      # JSON 構造化監査ログ
│       └── access.log       # テキスト形式ログ
└── plan/
    └── implementation_plan.md # 本計画書
```

---

## 3. 実装・検証タスク詳細

### タスク 1: 通信制御・プロキシ設定の最適化（完了）
- `squid/squid.conf`:
  - Docker 内部ネットワーク（RFC 1918 プライベートIP空間）からの接続のみを受け付ける。
  - リバースプロキシなど余分な設定を排し、ピュアなフォワードプロキシに特化。
  - `logformat json_audit` による詳細な JSON ログ定義。
- `squid/whitelist.txt`:
  - 主要 LLM（OpenAI, Anthropic, Gemini, Azure, AWS Bedrock 等）および GitHub ドメインを定義。

### タスク 2: コンテナとネットワークの定義（完了）
- `docker-compose.yml`:
  - `egress-proxy`: `internal-net` と `external-net` の両方に接続。
  - `goose-agent`: `internal-net` のみに接続（`internal: true`）。外部直接接続不可。
  - `GOOSE_TELEMETRY_ENABLED=false` をデフォルト適用。
- `goose/Dockerfile`:
  - 最新の Goose CLI をインストール。
  - 非 root ユーザー `sandboxuser` による最小権限実行。

### タスク 3: 通信遮断テストスイートの作成（完了）
- `bin/test-egress.sh`:
  1. **ホワイトリスト通信**: `curl --proxy http://egress-proxy:3128 https://api.openai.com` → 成功を確認。
  2. **非許可ドメイン通信**: `curl --proxy http://egress-proxy:3128 https://www.google.com` → 403 Forbidden 遮断を確認。
  3. **プロキシバイパス（直接通信）**: `curl --noproxy "*" --connect-timeout 3 https://api.openai.com` → `Network unreachable` で遮断を確認。

### タスク 4: 監査コマンド・UX整備（完了）
- `Makefile`:
  - `make test`: 通信遮断テストのワンクリック実行。
  - `make session`: Goose CLI セッション開始。
  - `make serve`: ホストの Goose Desktop から接続可能な ACP サーバー起動。
  - `make logs`: リアルタイム JSON 監査ログ監視。
  - `make audit-denied`: 遮断された通信のみを抽出表示。
  - `make audit-summary`: アクセス頻度トップ10ドメインを集計。

### タスク 5: GUI デスクトップ & Ingress プロキシ分離（完了）
- `nginx/nginx.conf`:
  - ホストからの noVNC Web UI / WebSocket (6080) および ACP (3284) を内部の `goose-agent` へ転送。
- `docker-compose.yml`:
  - `ingress-proxy` (Nginx), `egress-proxy` (Squid), `goose-agent` (隔離) の3層分離アーキテクチャ。
- `goose/Dockerfile` & `bin/start-desktop.sh`:
  - Xfce4 デスクトップ、Xvfb、noVNC、x11vnc、公式 Goose Desktop GUI (`.deb`)、Fcitx5 + Mozc 日本語入力を導入。

### タスク 6: 各種パラメータの .env 一元化 & 運用監視強化（完了）
- `.env` / `.env.example`:
  - ポート（`NOVNC_PORT`, `GOOSE_SERVE_PORT`, `SQUID_PORT`, `DOZZLE_PORT`）
  - 画面解像度（`RESOLUTION`）、タイムゾーン（`TZ=Asia/Tokyo`）、共有メモリ（`SHM_SIZE`）、UID/GID を一元設定可能に。
- Dozzle (Web ログビューワー: `http://localhost:8080`) の導入（PR #1 マージ）。
- ホワイトリスト動的リロード（`make reload`）および完全キルスイッチ（`make block-all` / `make unblock`）の導入。

---

## 4. 実動テスト手順と受入基準

| # | 検証項目 | コマンド / 手順 | 期待される結果 |
|---|---|---|---|
| 1 | イメージビルド | `make build` | Docker イメージが正常にビルドされること |
| 2 | 通信遮断テスト | `make test` | 3 つのテスト（ホワイトリスト通過、未許可遮断、直接バイパス遮断）が全て PASS すること |
| 3 | 監査ログの記録 | `make logs` または `cat logs/squid/access.json` | テスト実行時のリクエストが JSON 形式で記録されていること |
| 4 | 不正アクセスの検出 | `make audit-denied` | 未許可通信が `TCP_DENIED` として抽出表示されること |
| 5 | テレメトリの無効化 | コンテナ内環境変数確認 | `GOOSE_TELEMETRY_ENABLED=false` が有効であること |
| 6 | GUI デスクトップ | `http://localhost:6080/vnc.html` | Xfce4 デスクトップおよび Goose Desktop GUI が表示・操作可能であること |
| 7 | 日本語入力 | デスクトップ内ターミナル | Fcitx5+Mozc により日本語入力・変換ができること |
| 8 | Web ログ監視 | `http://localhost:8080` | Dozzle により全コンテナのログがリアルタイム閲覧できること |
| 9 | キルスイッチ | `make block-all` / `make unblock` | ワンコマンドで全通信遮断および復旧ができること |
