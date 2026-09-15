# Goose-in-the-Box: AI エージェント完全通信制御＆監査サンドボックス

[English](README.en.md) | [日本語](README.md)

AIエージェント「Goose」を安全に実行するための、Dockerベースの通信完全隔離・監査サンドボックスです。

Docker の `internal: true` ネットワーク（L3/L4）と Squid フォワードプロキシ（L7）の **2段構え** により、エージェントによる勝手な外部通信やデータ流出を 100% 遮断し、全通信試行を構造化 JSON ログに記録・監査します。また、Goose 本体の匿名テレメトリ送信もデフォルトで無効化されています。

---

## 主な特徴

- 🔒 **プロキシバイパスの完全排除 (L3/L4 隔離)**:
  - エージェントコンテナは `internal: true` ネットワーク内に配置され、外部へのデフォルトゲートウェイが存在しません。
  - プロキシ設定を無視した直接通信（IP直撃やDNS漏洩）を試みても、Linux カーネルが即座にパケットを破棄します。
- 🛡️ **厳格なホワイトリスト制御 (L7 制御)**:
  - 外部と通信可能な唯一の出口である Squid プロキシが、`whitelist.txt` に登録されたドメイン宛てのみ通過を許可します。未許可ドメインは `403 Forbidden` で即座に遮断されます。
- 📊 **JSON 構造化監査ログ**:
  - 全通信（許可・遮断・HTTPステータス・ドメイン・送受信量）を ISO8601 タイムスタンプ付きの JSON 形式で `/var/log/squid/access.json` に記録。CLI で即座にフィルタリング・集計が可能です。
- 🚫 **テレメトリ強制遮断**:
  - `GOOSE_TELEMETRY_ENABLED=false` が適用され、エージェント自体の利用データ送信を抑止します。

---

## ファイル構成

```text
goose-in-the-box/
├── docker-compose.yml       # 内部隔離(internal-net)と外部プロキシ(external-net)の定義
├── Makefile                 # ビルド、テスト、セッション起動、GUI、ログ監視、成果物出力
├── README.md                # 本ドキュメント
├── .env.example             # 設定パラメータ・APIキーテンプレート
├── squid/
│   ├── squid.conf           # 厳格なフォワードプロキシ設定 + JSON構造化監査ログ定義
│   └── whitelist.txt        # 許可ドメイン一覧（LLM, GitHub, PyPI, npm等）
├── nginx/
│   └── nginx.conf           # Ingressリバースプロキシ設定 (noVNC WebSocket / ACP中継)
├── goose/
│   └── Dockerfile           # Goose Desktop/CLI + Xfce4/noVNC + Fcitx5 + uv/npm/tmux
├── bin/
│   ├── test-egress.sh       # 通信遮断・プロキシ迂回防止・監査ログの自動検証スクリプト
│   ├── start-goose.sh       # AGENTS.md / ルール自動結合とGoose対話セッション起動
│   ├── start-desktop.sh     # Xfce4, VNC, websockify, Fcitx5, Goose Desktop 起動スクリプト
│   └── audit-tools.sh       # 監査ログ集計・違反検出スクリプト
├── workspace/               # Goose作業ディレクトリ（ホストとリアルタイム同期）
│   ├── .goosehints          # Goose公式プロジェクト指示書（日本語、Git、tmux、uv優先）
│   ├── .gitignore           # ワークスペース標準除外設定（Python, Node, uv, OS一時ファイル）
│   ├── AGENTS.md            # 作業ルール・セキュリティガイドライン
│   └── .agents/             # スキルや分割ルールの配置場所
├── config/                  # Goose 設定ディレクトリ（ホストとマウント永続化）
│   └── config.yaml          # プロバイダー（Ollama等）および拡張機能設定
├── data/                    # Goose 内部データの永続化マウント先
│   ├── sessions/            # 会話セッション履歴 DB (Chat Recall用)
│   └── logs/                # Goose 内部ログ
├── logs/                    # Squid 監査ログ出力先（ホストから閲覧可能）
│   └── squid/
│       ├── access.json      # JSON 構造化監査ログ
│       └── access.log       # テキスト形式ログ
└── plan/
    ├── implementation_plan.md # 実装計画書 (v4: スターター・MCP環境完備)
    └── memo.md              # 実装仕様・要件メモ
```

## 設定パラメータ (.env)

環境設定はすべて `.env` ファイルで一元管理できます（`.env.example` を参考に設定）。

| パラメータ | 説明 | デフォルト値 |
| :--- | :--- | :--- |
| **`HOST_BIND`** | ホスト側公開IPバインド設定（全公開: `0.0.0.0`、ローカル限定: `127.0.0.1`、指定NIC-IP） | `0.0.0.0` |
| **`OPENAI_API_KEY` 等** | 各種 LLM プロバイダーの API キー | （空欄） |
| **`OPENAI_BASE_URL`** | OpenAI互換エンドポイント (さくらAI, vLLM, LocalAI等) ※末尾スラッシュなし | `https://api.openai.com/v1` |
| **`OPENAI_HOST`** | OpenAI互換ホスト名 (プロバイダー解決用) | `https://api.openai.com` |
| **`OLLAMA_HOST`** | ローカル LLM ホスト接続先 (ポート11434) | `http://host.docker.internal:11434` |
| **`NOVNC_PORT`** | noVNC Web UI ポート（ブラウザ接続先） | `6080` |
| **`GOOSE_SERVE_PORT`** | Goose ACP サーバー公開ポート | `3284` |
| **`SQUID_PORT`** | Squid 監査プロキシポート | `3128` |
| **`DOZZLE_PORT`** | Dozzle Web リアルタイムログ監視ポート | `8080` |
| **`RESOLUTION`** | 仮想デスクトップ解像度 | `1280x800x24` |
| **`TZ`** | タイムゾーン（時計・ログ出力時刻） | `Asia/Tokyo` |
| **`SHM_SIZE`** | 共有メモリサイズ（GUI安定化用） | `1gb` |
| **`UID` / `GID`** | コンテナ内実行ユーザー権限 | `1000` / `1000` |
| **`GOOSE_TELEMETRY_ENABLED`** | 匿名の利用実績データ送信制御 | `false` |

---

## クイックスタート

### 1. 初期設定
```bash
cp .env.example .env
# .env を開いて必要な API キーや設定を調整
```

### 2. コンテナイメージのビルド
```bash
make build
```

### 3. 通信遮断の実動テスト
隔離環境内から検証スクリプトを実行し、通信制御が正常に働いているかテストします：
```bash
make test
```
**テスト内容:**
1. ✅ **ホワイトリストドメイン (`api.openai.com`)**: プロキシ経由で正常に接続
2. 🛑 **非許可ドメイン (`www.google.com`)**: Squid プロキシが `403 Forbidden` で遮断
3. 🔒 **直接接続バイパス**: Docker `internal: true` により `Network unreachable` で遮断

---

## Goose の実行

### CLI 対話セッション
`workspace/AGENTS.md` や `.agents/rules/*.md` のルールを自動読み込みし、隔離環境内で Goose CLI を開始します：
```bash
make session
```

### Goose Desktop（GUI）との連携
ACP サーバーを起動し、ホスト側の Goose Desktop から接続して作業します：
```bash
make serve
```
* ホスト側 Goose Desktop の接続先: `http://localhost:3284`

### コンテナ内 GUI デスクトップの利用 (noVNC / ブラウザ操作)
エージェントにブラウザを操作させたり、コンテナ内の画面を丸ごと確認・操作したい場合は、GUI デスクトップ環境を起動します：
```bash
make gui
```
* 起動後、ホストのブラウザで **`http://localhost:6080/vnc.html`** を開くと、隔離コンテナ内の Xfce4 デスクトップがそのままブラウザ上に表示されます。
* VNC クライアントから接続する場合は `localhost:5900` にアクセスします。

---

## 通信ログの監査・分析

### Dozzle によるリアルタイムWebログ監視
Dozzle が `docker-compose.yml` に定義されており、ブラウザからコンテナのログをリアルタイムに確認・検索・フィルタリングできます：
* **`http://<ホストIP>:8080`** にアクセス (例: `http://localhost:8080` や `http://blue-two.local:8080`)
* `egress-proxy` コンテナを選択することで、Squid のアクセスログ（`TCP_TUNNEL/200` や `TCP_DENIED/403` など）をヘルスチェックのノイズなしで監視可能です。

### CLI でのリアルタイム監査ログの閲覧
```bash
make logs
```

### リアルタイムカラーアラート監視
拒否された通信を即座に検出し、ターミナルにカラー表示します（ストーム抑制・Webhook通知対応）：
```bash
make watch
```

### 遮断された通信 (403 DENIED) の一覧抽出
エージェントがアクセスを試みてブロックされたドメインや URL を確認します：
```bash
make audit-denied
```

### 宛先ドメイン別アクセス頻度・転送量集計
```bash
make audit-summary
```

### Ingress (外部からコンテナへの接続) 監査ログ
noVNC や ACP サーバーへの接続履歴を一覧表示します：
```bash
make audit-ingress
```

### 監査ログ・LLM可観測性ダッシュボード & API
Squid の JSON ログ (`/var/log/squid/access.json`) を解析し、**人間向け Web ダッシュボード**と **LLM 向け構造化 API (JSON / Markdown)** を一括生成・配信します：

- `user_agent`: 通信を発生させたツールやライブラリの特定
- `bytes_sent` / `bytes_received`: 送受信バイト数から LLM 消費トークン・コストを概算推計 (±50%目安)
- `duration_ms`: レスポンス所要時間（ミリ秒）
- `alerts`: 通信遮断率スパイクや大容量転送の事前評価アラート

```bash
# ダッシュボードおよび JSON / Markdown API を即時手動生成
make report

# LLM エージェント監視用に JSON のみ stdout に出力
make report-json
```

- 🔄 **常時自動更新 (`report-watcher`)**:
  - Docker Compose 起動中 (`make up-proxy` または `docker compose up -d`)、専用のバックグラウンドワーカーが **30秒ごとに自動集計** を継続実行します。ターミナルで監視プロセスを手動起動し続ける必要はありません（更新間隔は `.env` の `REPORT_INTERVAL` で調整可能）。
- 📊 **Web UI ダッシュボード**: `http://<ホストIP>:6080/report/` (30秒自動リフレッシュ、noVNC・Dozzle への相互リンク付き)
- 🤖 **LLM 向け JSON API**: `http://<ホストIP>:6080/report/api/status.json` (`curl` や LLM が即座にパース・判定可能)
- 📝 **LLM 向け Markdown 要約**: `http://<ホストIP>:6080/report/api/summary.md` (コンテキスト消費を最小化するテキスト要約)
- ⚙️ **プロバイダー単価・閾値設定**: `config/llm-pricing.json` でモデル単価や為替レート、アラート基準値を柔軟に調整可能

### セッション別（日付別）の通信傾向比較
過去にローテーションされたログも含め、セッション横断で通信傾向を比較集計します：
```bash
make audit-history
```

### 監査ログの手動ローテーション
```bash
make log-rotate
```

---

## ドメインホワイトリストの動的制御 & 完全キルスイッチ

### ドメインの動的オン/オフ (リロード)
許可するドメインを追加・変更したい場合は、ホスト側の `squid/whitelist.txt` を編集後、以下のコマンドで Squid の設定を即時反映します：
```bash
# squid/whitelist.txt を編集後に実行
make reload
```
*(通信を切断・再接続することなく即時にホワイトリスト変更が適用されます)*

### 完全キルスイッチ（一括オン/オフ）
緊急時などに CLI から全通信を瞬時にシャットダウン・復元できます：
```bash
# 全通信を緊急遮断（ホワイトリストを空にして reconfigure）
make block-all

# 通信遮断を解除（ホワイトリストを復元して reconfigure）
make unblock
```

---

## 開発スターター環境 & MCP 基盤

本サンドボックスは、AI エージェントが自律的にコーディング・ツール利用（MCP）を行えるよう、ベストプラクティス構成が最初から整えられています：

1. **基本ツール & Git 自動設定**:
   - `git` は `user.name`（Goose Agent）、`user.email`、`safe.directory`、`defaultBranch` が事前設定済み。
   - `tmux`（セッション永続化・バックグラウンド管理、マウス有効化）
   - 基本ユーティリティ: `build-essential`（make, gcc等）、`wget`、`unzip`、`nano`、`less`、`htop`、`tree`
2. **言語ランタイム & MCP 拡張基盤**:
   - **Python 3.11** + **`uv` / `uvx`**: 高速パッケージ管理およびオンデマンド MCP サーバー実行。
   - **`pipx`**: 隔離環境での CLI ツール実行。
   - **Node.js** + **`npm` / `npx`**: TypeScript/JavaScript 系 MCP サーバー実行基盤。
3. **公式準拠のプロジェクト指示 (`.goosehints`)**:
   - `/workspace/.goosehints` に日本語対応、Git コミット指針、ハングアップ防止（常駐サーバーは `tmux` で起動）などのベストプラクティスが定義されています。

---

## 成果物のローカル共有 & エクスポート

1. **ホストマシンとのリアルタイム共有 (バインドマウント)**:
   - Goose が `/workspace` 配下に作成・編集したコードやファイルは、ホスト側の `./workspace/` にリアルタイムで直接反映されます。手元のエディタ（VS Code, IDE等）で即座に閲覧・編集可能です。
2. **ワンライナーでの成果物アーカイブ**:
   - 成果物一式をタイムスタンプ付き tar.gz アーカイブとして書き出したい場合は、以下のコマンドを実行します：
     ```bash
     make export-workspace
     ```
     `exports/workspace_YYYYMMDD_HHMMSS.tar.gz` にアーカイブが出力されます。
