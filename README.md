# Geese-in-the-Box (旧 Goose-in-the-Box): 複数AIエージェントのネットワーク隔離・監査サンドボックス基盤

[![CI Sandbox Egress & Audit Test](https://github.com/chottokun/Geese-in-the-Box/actions/workflows/ci.yml/badge.svg)](https://github.com/chottokun/Geese-in-the-Box/actions/workflows/ci.yml)

## 📌 プロジェクト概要 (What is Geese-in-the-Box?)
**Geese-in-the-Box**（旧 Goose-in-the-Box）は、Goose、OpenCode、OpenClaw 2.0 などの自律型 AI エージェントを、安全に隔離・実行するための「Docker 隔離 + Squid 監査プロキシ基盤」です。AIエージェントの通信状況を監視しながら動作をさせることができます。

自律型AIエージェントに直接ホストの権限やネットワークを与えると、以下のようなリスクがあります。
- 未許可の外部サーバーへのデータ送信（情報漏洩）
- クレデンシャル（秘密鍵や API キー）の流出
- ホスト環境そのものへの侵害・破壊

Geese-in-the-Box は、これらのリスクをある程度解決し、エージェントが安全に思考・実行できる環境を提供します。また、通信を監視・管理・制御することもできます。

なお、本プロダクトは個人開発による実験的な取り組みで、高度なセキュリティ的評価を行ったプロダクトではありません。

---

## 🏛️ アーキテクチャ概要 (Architecture Overview)

本基盤のコンセプトは、**二重防御モデル (Defense in Depth)** です。

1. **L3/L4 ネットワーク隔離 (Docker `internal: true`)**:
   - AI エージェントは外部インターネットから完全に切り離された専用の内部ネットワークで動作します。
2. **L7 ホワイトリストプロキシ (Squid)**:
   - エージェントが外部と通信する際は、Squid プロキシを経由する必要があります。
   - 事前に許可されたドメイン（例: `api.openai.com`, `github.com`）のみ接続でき、それ以外はすべて `403 Forbidden` で遮断・監査されます。

### サポートエージェント一覧
- **Goose Agent** (Block社製 / CLI・GUI対応)
- **OpenCode** (オープンソース / ターミナル・GUI対応)
- **OpenClaw 2.0** (最新自律エージェント / ターミナル・GUI対応)

---

## 🚀 直感的なクイックスタート (Quickstart in 3 Steps)

### Step 1: 初期設定
まずは `.env` ファイルを作成し、各種 API キーや設定を行います。
```bash
cp .env.example .env
```
> [!TIP]
> `.env` には OpenAI や Anthropic などの API キーを設定します。ローカルLLM (Ollama等) を使用する場合は不要です。

### Step 2: 起動
Docker イメージをビルドし、エージェントを起動します。用途に合わせてコマンドを選択してください。

```bash
# 基本ビルド (Goose + プロキシ基盤)
make build

# Goose CLI 対話セッション
make session
```

**各エージェントの起動コマンド**:
- **Goose**:
  - ターミナル: `make session`
  - GUI (ブラウザ仮想デスクトップ): `make gui`
- **OpenCode**:
  - ビルド: `make build-opencode`
  - ターミナル: `make run-opencode`
  - GUI (ブラウザ仮想デスクトップ): `make run-opencode-gui`
- **OpenClaw 2.0**:
  - ビルド: `make build-openclaw`
  - ターミナル: `make run-openclaw`
  - GUI (ブラウザ仮想デスクトップ): `make run-openclaw-gui`

**コンテナの再作成・リセット & 実行オプション**:
- **コンテナ破棄・強制再作成**: `make recreate` (既存コンテナを破棄してイメージから再生成)
- **キャッシュなし再ビルド**: `make rebuild`
- **全破棄・初期化**: `make clean-all` (全コンテナ・全ボリュームを削除)
- **コンテナ状態の保持 (`--rm` 制御)**: `RM=0 make <コマンド>` (終了時にコンテナを破棄せず保持して次回も継続可能。デフォルトは `RM=1` でクリーン自動破棄)
- **GPU 有効化**: `USE_GPU=1 make <コマンド>`

### Step 3: 操作・確認 (統合 UI)
エージェントが動作し始めたら、ブラウザから通信制御や監視、GUI操作が可能です。
- **コントロールパネル**: `http://localhost:6080/control/` （キルスイッチ・ホワイトリスト管理）
- **Dozzle (コンテナログ)**: `http://localhost:8080/`
- **仮想デスクトップ (noVNC)**:
  - Goose: `http://localhost:6080/vnc.html`
  - OpenCode: `http://localhost:6081/vnc.html`
  - OpenClaw 2.0: `http://localhost:6082/vnc.html`

---

## ✨ 主要機能紹介

### 🎛️ 統合コントロールパネル (`make control`)
Web UI からリアルタイムにホワイトリストの編集や通信ブロックが行えます。
![Geese-in-the-Box 統合コントロールパネル](docs/images/control-panel.png)
- 🔒 **緊急キルスイッチ**: ワンクリックでエージェントの全外部通信を即座に遮断。
- ⏳ **一時ホワイトリスト化**: 遮断された通信ログから 15分/1時間の一時許可を付与。

### 📊 監査・可観測性ダッシュボード
Squid の JSON ログを自動集計し、トラフィック量やアラート推移を可視化します。
![Geese-in-the-Box 監査・可観測性ダッシュボード](docs/images/audit-dashboard.png)
- **Web UI ダッシュボード**: `http://localhost:6080/report/`

### 🖥️ noVNC ブラウザデスクトップ環境
GUI エージェントの動作を視覚的に確認・介入できるブラウザ完結型の Xfce4 デスクトップ環境を内蔵しています（Goose: `:6080`、OpenCode: `:6081`、OpenClaw: `:6082`）。日本語入力 (Fcitx5) にも対応。

### 🔄 複数エージェント切り替え対応
一つの安全な基盤の上で、Goose、OpenCode、OpenClaw を並行運用したりすることが可能です。

### ⚡ 選択的 GPU (NVIDIA CUDA) パススルー
機械学習スクリプトや GPU を必要とするタスク向けに、ホストの NVIDIA GPU をオンデマンドでコンテナに割り当て可能です。安全のためデフォルトは CPU のみで動作します。
- **一時的に有効化**: コマンドの先頭に `USE_GPU=1` を付与（例: `USE_GPU=1 make session`, `USE_GPU=1 make run-opencode-gui`）
- **常時有効化**: `.env` に `USE_GPU=true` を設定

---

## 🛡️ セキュリティ境界 (Security Boundaries)

### 🟢 保証すること (Guarantees)
- エージェントコンテナから外部への直接通信の遮断 (Docker L3/L4 隔離)
- 許可されたドメイン以外の L7 (HTTP/HTTPS) 通信の遮断と監査記録 (Squid プロキシ)
- プロキシを経由しない不透明なバイパス通信の防止

### 🔴 スコープ外事項 (Non-Goals)
- エージェントが故意・悪意を持って難読化されたコードをホストにバインドされた `/workspace` 領域に書き込むことの防止 (ワークスペースはユーザー責任でレビューする必要があります)
- 許可されたホワイトリストドメイン (例: `github.com`) を悪用したデータの持ち出し手法 (DNSトンネリング等を除く)

---

## 📚 ドキュメント導線 (LLM-Wiki / Docs Navigation)

より詳細な技術アーキテクチャやドメイン知識については、内部の LLM-Wiki を参照してください。

- 📖 **[Geese-in-the-Box LLM-Wiki インデックス (docs/README.md)](docs/README.md)**
- [多層防御モデル (Architecture)](docs/architecture/isolation_model.md)
- [コントロールパネルの仕組み (Infrastructure)](docs/infrastructure/control_panel.md)
- [エージェント比較と並行運用 (Domain)](docs/domain/agents_comparison.md)

---

## ライセンス
本プロジェクトは [MIT License](LICENSE) の下で公開されています。
