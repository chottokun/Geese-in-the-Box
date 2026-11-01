---
type: "infrastructure"
title: "統合ポートマップ仕様書"
description: "Geese-in-the-Box における内部/外部ポート割り当ておよびルーティング体系"
status: "stable"
tags: ["port", "networking", "novnc", "ingress", "architecture"]
---

# 統合ポートマップ仕様書

Geese-in-the-Box では、複数の AI エージェント（Goose, OpenCode, OpenClaw, DeepSeek Harness, Hermes Agent）および監査・可観測性コンテナが稼働します。
ポートの競合を防止し、直感的なアクセスを提供するため、ポート番号を体系的に分類・管理しています。

ポートのデフォルト設定は [config/ports.env](file:///home/nobuhiko/Project/goose-in-the-box/config/ports.env) に定義されており、`.env` で任意に上書きできます。

## ポート体系一覧

| ポート番号帯 | 用途分類 | 対象サービス / エージェント | 説明 |
|---|---|---|---|
| **6080〜6089** | **noVNC 仮想デスクトップ** | `6080`: Goose<br>`6081`: OpenCode<br>`6082`: OpenClaw<br>`6083`: DeepSeek Harness (`dsh`)<br>`6084`: Hermes Agent | ブラウザで Xfce4 デスクトップを開くポート。`http://localhost:<ポート>/vnc.html` で接続します。 |
| **3000番台** | **プロトコル・監査プロキシ** | `3128`: Squid (`egress-proxy`)<br>`3284`: Goose ACP (`ingress-proxy`) | 外部通信監査用フォワードプロキシおよび Goose 固有の ACP サーバー接続ポートです。 |
| **8000番台** | **監視・ダッシュボード** | `8080`: Dozzle<br>*(内部 8000)*: Control Panel | リアルタイムログ監視画面。Control Panel は `http://localhost:6080/control/` 経由でリバースプロキシされます。 |
| **18000番台** | **固有 Gateway / Web UI** | `18789`: OpenClaw Gateway | エージェント固有のバックエンド Web UI や RPC ポートです。 |

## 各エージェントへのアクセス URL

| エージェント | GUI (noVNC) URL | CLI 起動コマンド | 備考 |
|---|---|---|---|
| **Goose** | `http://localhost:6080/vnc.html` | `make session` | デフォルトエージェント |
| **OpenCode** | `http://localhost:6081/vnc.html` | `make run-opencode` | `--profile opencode` |
| **OpenClaw** | `http://localhost:6082/vnc.html` | `make run-openclaw` | `--profile openclaw`<br>Web UI: `:18789` |
| **DeepSeek Harness** | `http://localhost:6083/vnc.html` | `make run-dsh` | `--profile dsh`<br>Web UI / Desktop / CLI を内包 |
| **Hermes Agent** | `http://localhost:6084/vnc.html` | `make run-hermes` | `--profile hermes`<br>Terminal TUI を内包 |
