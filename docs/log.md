---
type: "log"
title: "OKF 運用変更ログ"
description: "LLM-Wiki (OKF) ナレッジベースの作成・更新履歴"
generated: { by: "jules/1.0", at: "2026-09-21T10:40:00Z" }
verified:
  - { by: "human:nobuhiko", at: "2026-09-21T10:45:00Z" }
status: "stable"
tags: ["log", "changelog"]
---

# OKF 運用変更ログ

本ドキュメントは、LLM-Wiki の各ドキュメント（OKF 準拠）の作成および更新履歴を記録します。

## [2026-09-21] 初期構築 (v1.0.0)

- **追加**: `docs/README.md` (全体マップとインデックス)
- **追加**: `docs/log.md` (本変更ログ)
- **追加**: `docs/architecture/isolation_model.md` (Docker internal ネットワーク隔離仕様)
- **追加**: `docs/architecture/ingress_routing.md` (Nginx による Ingress 中継と監査)
- **追加**: `docs/architecture/egress_control.md` (Squid プロキシとキルスイッチ)
- **追加**: `docs/infrastructure/control_panel.md` (Control Panel の設計)
- **追加**: `docs/infrastructure/observability.md` (ダッシュボードと監査レポート)
- **追加**: `docs/infrastructure/desktop_environment.md` (Xfce4, noVNC, 日本語入力)
- **追加**: `docs/domain/agents_comparison.md` (Goose と OpenCode の比較)
- **追加**: `docs/domain/workspace_sharing.md` (共有ワークスペースの運用)
- **備考**: OKF v0.2 のテンプレートに基づき、全体的な技術ドキュメント群を初版として作成。
