---
type: "domain"
title: "Goose, OpenCode, OpenClaw の比較・並行運用"
description: "Goose Agent, OpenCode Agent, OpenClaw Agent の特徴比較と、同一サンドボックス内での並行運用設計"
generated: { by: "jules/1.0", at: "2026-09-21T10:40:00Z" }
verified:
  - { by: "human:Chottokun", at: "2026-09-21T10:45:00Z" }
status: "stable"
tags: ["goose", "opencode", "openclaw", "agent", "comparison", "parallel"]
---

# Goose, OpenCode, OpenClaw の比較・並行運用

Geese-in-the-Box は、Block チームが開発する **Goose Agent** 、オープンソースのコーディングエージェント **OpenCode**、そして最新のエージェント **OpenClaw** を、同じ安全なサンドボックス境界内でサポートします。

## エージェントの比較

| 特徴 | Goose Agent | OpenCode | OpenClaw |
|:---|:---|:---|:---|
| **コア設計** | 汎用 AI エージェント（システム操作、ブラウザ操作、コーディング） | コーディングとソフトウェア開発に特化したエージェント | 高度な推論とメッセージング連携（Telegram/Discord）を備えたエージェント |
| **アーキテクチャ** | Rust CLI + Electron GUI | Python バックエンド + Vue/React フロントエンド | Python バックエンド + Control UI |
| **拡張性** | MCP (Model Context Protocol) サーバーによる動的拡張を公式サポート | 独自プラグイン/ツール群 | 組み込みツールとメッセージング連携拡張 |
| **インターフェース** | TUI (Terminal UI), Desktop GUI, ACP Server (外部アプリ接続) | TUI, Web GUI (独自ダッシュボード) | TUI, Control UI (ポート 18789) |
| **ホスト連携** | `make session` による直接対話, `make gui` (noVNC: 6080) | `make run-opencode` (TUI), `make run-opencode-gui` (noVNC: 6081) | `make run-openclaw` (TUI), `make run-openclaw-gui` (noVNC: 6082) |

## 並行運用設計 (Parallel Operation)

1 つのプロジェクト（ワークスペース）に対して、目的の異なる複数の AI エージェントを同時に、または切り替えて使用できるよう設計されています。

### コンテナの分離とポートの重複回避
- Goose は `goose-agent` コンテナ、OpenCode は `opencode-agent` コンテナ、OpenClaw は `openclaw-agent` コンテナとしてそれぞれ独立して稼働します。
- `opencode-agent` および `openclaw-agent` は Docker Compose の profiles機能 (`opencode`, `openclaw`) によって定義されており、明示的にビルド・起動（`make build-opencode`, `make run-openclaw`等）しない限りリソースを消費しません。
- これらは noVNC による仮想デスクトップを提供しますが、ポート競合を防ぐため Nginx で以下のようにルーティングを分けています：
  - Goose: `:6080`
  - OpenCode: `:6081`
  - OpenClaw: `:6082`

### ネットワーク監査の統一
どのコンテナから発生したトラフィックであっても、Docker の `internal-net` に属しているため、通信は必ず同じ `egress-proxy` (Squid) を通過します。
これにより、キルスイッチ（`make block-all`）を発動させると、全てのエージェントの通信が同時に遮断されます。
監査ログ (`access.json`) には、コンテナの IP アドレス（`remote_addr`）や `user_agent` が記録されるため、どのエージェントが通信を行ったかを事後分析することが可能です。

## OpenClaw 2.0 のモデルルーティングとフォールバック仕様

OpenClaw 2.0 では、メインの推論タスクとセッション補助タスクで異なるモデルを割り当てるルーティング機構を備えています。

### 1. Primary Model と Utility Model
- **Primary Model**: ユーザーとの会話、コード生成、推論の主処理を担当。`.env` の `OPENCLAW_MODEL` または `GOOSE_MODEL` から動的に反映されます。
- **Utility Model**: セッションタイトルの生成、メタデータ抽出、状態ダイジェスト生成などの軽量なバックグラウンドタスクを担当。

### 2. ユーティリティモデルの自動フォールバック挙動
- OpenClaw 内部では、プロバイダーが OpenAI（または OpenAI 互換エンドポイント）の場合、既定のユーティリティモデルとして `gpt-5.6-luna` などのデフォルト値が定義されています。
- さくらAIや vLLM、LocalAI などのカスタムエンドポイントを利用している環境では、該当するデフォルトモデルが存在しないため、ユーティリティタスクの呼び出し時に `400 Bad Request` が返されることがあります。
- **動作継続性 (Graceful Fallback)**: この 400 エラーが発生しても、OpenClaw はシステム全体を停止させず、内部的にフォールバックしてメインモデル（Primary Model）での対話・実行を通常通り継続します。そのため、設定を明示的に変更しなくても運用上の問題はありません。
- **明示的な指定・無効化**: 不要なエラーログの出力を抑止したい場合は、`~/.openclaw/openclaw.json` の `agents.defaults` にて `utilityModel` を Primary Model と同一に設定するか、空文字 `""` を指定してユーティリティルーティングを無効化できます。

