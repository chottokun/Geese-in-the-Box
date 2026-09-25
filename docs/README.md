---
type: "index"
title: "Geese-in-the-Box LLM-Wiki 全体マップ"
description: "Geese-in-the-Box のアーキテクチャ・運用・ドメイン知識をまとめた LLM-Wiki のインデックスと全体マップ"
generated: { by: "jules/1.0", at: "2026-09-21T10:40:00Z" }
verified:
  - { by: "human:Chottokun", at: "2026-09-21T10:45:00Z" }
status: "stable"
tags: ["index", "wiki", "okf"]
---

# Geese-in-the-Box (旧 Goose-in-the-Box) LLM-Wiki 全体マップ

本ドキュメントは、Geese-in-the-Box (旧 Goose-in-the-Box) の技術アーキテクチャ、インフラ構成、ドメイン知識を統合した LLM-Wiki（ナレッジベース）のインデックスです。
各ドキュメントは OKF (Open Knowledge Format) v0.2 に準拠し、技術者および AI エージェントがシステム構成を深く理解するために構造化されています。

## 信頼度ティア (Reliability Tiers)
本 Wiki 内のドキュメントは以下の信頼度ティアに分類されます。
- **Tier 1 (Core)**: 基礎アーキテクチャ、セキュリティモデル、ネットワーク隔離仕様 (最も信頼性が高く、変更頻度が低い)
- **Tier 2 (Infrastructure)**: コンテナ構成、管理UI、可観測性基盤などのインフラ要素
- **Tier 3 (Domain)**: ワークフロー、エージェント運用、拡張方針などのドメイン固有知識

## OKF 概念インデックスとドキュメントリンク

### 📁 アーキテクチャ (Architecture) - Tier 1
Docker internal ネットワーク隔離とプロキシ多層防御に関する中核設計。
- [完全多層防御モデル (L3/L4/L7)](architecture/isolation_model.md)
- [Ingress ルーティングと監査 (Nginx)](architecture/ingress_routing.md)
- [Egress 通信制御とキルスイッチ (Squid)](architecture/egress_control.md)

### 📁 インフラストラクチャ (Infrastructure) - Tier 2
統合管理や可観測性、デスクトップ環境などのインフラ要素。
- [コントロールパネル (FastAPI)](infrastructure/control_panel.md)
- [可観測性とダッシュボード (Dozzle / Report-Watcher)](infrastructure/observability.md)
- [仮想デスクトップ環境 (Xfce4 / Fcitx5 / noVNC)](infrastructure/desktop_environment.md)

### 📁 ドメイン (Domain) - Tier 3
AI エージェントの並行運用やワークスペース管理などの運用知識。
- [CLI 使い方・運用ガイド](domain/cli_guide.md)
- [Goose, OpenCode, OpenClaw の比較・並行運用](domain/agents_comparison.md)
- [ワークスペース共有と協調ワークフロー](domain/workspace_sharing.md)

## 変更ログ
- [OKF 運用変更ログ](log.md)

