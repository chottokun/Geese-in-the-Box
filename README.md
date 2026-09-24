# Geese-in-the-Box (旧 Goose-in-the-Box): 複数AIエージェントのネットワーク隔離・監査サンドボックス基盤

[![CI Sandbox Egress & Audit Test](https://github.com/chottokun/Geese-in-the-Box/actions/workflows/ci.yml/badge.svg)](https://github.com/chottokun/Geese-in-the-Box/actions/workflows/ci.yml)

## 📌 プロジェクト概要 (What is Geese-in-the-Box?)
**Geese-in-the-Box**（旧 Goose-in-the-Box）は、Goose、OpenCode、OpenClaw 2.0 などの自律型 AI エージェントを、安全に隔離・実行するための「Docker 隔離 + Squid 監査プロキシ基盤」です。

**なぜ必要なのか？**
野良の AI エージェントや自律型コーディングエージェントに直接ホストの権限やネットワークを与えると、以下のようなリスクがあります。
- 未許可の外部サーバーへのデータ送信（情報漏洩）
- クレデンシャル（秘密鍵や API キー）の流出
- ホスト環境そのものへの侵害・破壊

Geese-in-the-Box はこれらのリスクを「多層防御」により解決し、エージェントが安全に思考・実行できるサンドボックスを提供します。

---

## 🏛️ アーキテクチャ概要 (Architecture Overview)

本基盤の最も重要なコンセプトは、**二重防御モデル (Defense in Depth)** です。

1. **L3/L4 ネットワーク隔離 (Docker `internal: true`)**:
   - AI エージェントは外部インターネットから完全に切り離された専用の内部ネットワークで動作します。
2. **L7 ホワイトリストプロキシ (Squid)**:
   - エージェントが外部と通信する際は、Squid プロキシを経由する必要があります。
   - 事前に許可されたドメイン（例: `api.openai.com`, `github.com`）のみ接続でき、それ以外はすべて `403 Forbidden` で遮断・監査されます。

### サポートエージェント一覧
- **Goose Agent** (Block社製)
- **OpenCode** (オープンソース)
- **OpenClaw 2.0** (最新GUI対応エージェント)

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
# ビルド
make build
# Goose CLI 対話セッション
make session
```

**その他のエージェント起動コマンド**:
- **Goose GUI (ブラウザ仮想デスクトップ)**: `make gui`
- **OpenCode (ターミナル)**: `make run-opencode`
- **OpenClaw 2.0 (GUI)**: `make run-openclaw-gui`

### Step 3: 操作・確認 (統合 UI)
エージェントが動作し始めたら、ブラウザから通信制御や監視が可能です。
- **コントロールパネル**: `http://localhost:6080/control/` （キルスイッチ・ホワイトリスト管理）
- **Dozzle (コンテナログ)**: `http://localhost:8080/`
- **仮想デスクトップ (noVNC)**: `http://localhost:6080/vnc.html` (Gooseの場合)

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
GUI エージェントの動作を視覚的に確認・介入できるブラウザ完結型の Xfce4 デスクトップ環境を内蔵しています。日本語入力 (Fcitx5) にも対応。

### 🔄 複数エージェント切り替え対応
一つの安全な基盤の上で、Goose、OpenCode、OpenClaw を自由に切り替えたり並行運用したりすることが可能です。

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
