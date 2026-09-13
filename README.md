# Goose Egress Sandbox Package

AIエージェント「Goose」を隔離環境で安全に実行するためのDockerサンドボックスパッケージです。
SquidフォワードプロキシとDockerの `internal: true` ネットワークを組み合わせ、許可したドメイン以外への通信をカーネル/プロキシの2段構えで遮断します。
また、Gooseの匿名利用データ（テレメトリ）送信もデフォルトで無効化（`GOOSE_TELEMETRY_ENABLED=false`）されています。

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
│   ├── test-egress.sh       # 通信遮断検証スクリプト
│   └── start-goose.sh       # AGENTS.md/CLAUDE.mdを読み込んでGooseを起動
└── workspace/               # Goose作業用ディレクトリ（ホストとバインドマウント）
    ├── AGENTS.md            # プロジェクト固有の作業ルール・指示
    ├── .agents/skills/      # プロジェクト固有のスキル定義
    └── .agents/rules/       # 分割ルール定義（任意: .md ファイルを自動結合）
```

## クイックスタート

### 1. 初期設定
```bash
cp .env.example .env
# 必要に応じて .env に APIキーを設定
```

### 2. コンテナのビルドとプロキシ起動
```bash
make build
make up-proxy
```

### 3. 通信遮断テストの実行
Gooseコンテナを起動し、内部から検証スクリプトを実行して正しくホワイトリスト制御されているか確認します。
```bash
make test
```
* ホワイトリスト登録ドメインは通過
* 未許可ドメインは `403 Forbidden` で遮断
* プロキシを経由しない直接通信は `Network unreachable` で遮断

### 4. Gooseの起動

#### CLIで利用する場合
`workspace/AGENTS.md`（または `CLAUDE.md`）のルールを自動で読み込み、隔離環境内の対話CLIを開始します：
```bash
make session
```

#### Goose Desktop（デスクトップアプリ）から利用する場合
サンドボックス内で ACP（Agent Client Protocol）サーバーを起動し、ホストマシンの Goose Desktop から接続して利用します：
```bash
make serve
```
* ホスト側の Goose Desktop で、接続先エージェントとして `http://localhost:3284` を指定してセッションを開始します。
* これにより、GUIフロントエンドの快適さを維持しながら、すべてのコマンド実行・ファイル変更・外部通信制御を隔離コンテナ内で実行できます。

### 5. スキル・ルールのワークスペース内管理
ホスト環境に依存せず、すべてのルール・スキルは `workspace/` 配下で完結します：
* **スキル**: `workspace/.agents/skills/` 配下に `SKILL.md` を配置すると、Gooseのツールとして認識されます。
* **ルール**: `workspace/AGENTS.md`（または `CLAUDE.md`）に記載します。ルールを分割したい場合は `workspace/.agents/rules/*.md`（または `.rules/*.md`）に配置すると、`make session` 実行時に自動で結合・適用されます。

## プロキシログのリアルタイム監査
ホスト側からプロキシのアクセスログを監視できます：
```bash
make logs
```
