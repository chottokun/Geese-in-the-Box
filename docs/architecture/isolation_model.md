---
type: "architecture"
title: "ネットワーク隔離と多層防御モデル"
description: "Docker の internal ネットワークによる L3/L4 隔離と Squid/Nginx による L7 プロキシの多層防御アーキテクチャ"
generated: { by: "jules/1.0", at: "2026-09-21T10:40:00Z" }
verified:
  - { by: "human:nobuhiko", at: "2026-09-21T10:45:00Z" }
status: "stable"
tags: ["docker", "network", "security", "isolation", "proxy"]
---

# ネットワーク隔離と多層防御モデル

Goose-in-the-Box における最も重要なセキュリティ基盤は、AI エージェントが実行されるコンテナ環境をホストおよび外部インターネットから確実に隔離する「多層防御 (Defense in Depth)」アプローチです。

## 基本アーキテクチャ (Defense in Depth)

本システムは以下の 3 つの層でセキュリティ境界を構築しています。

1. **L3/L4 隔離 (Network Layer)**: Docker の `internal: true` ネットワーク
2. **L7 Egress 制御 (Application Layer)**: Squid による宛先ドメインのホワイトリスト制
3. **L7 Ingress 制御 (Application Layer)**: Nginx によるホスト側からの安全な中継

```mermaid
graph TD
    subgraph "Host Machine"
        Browser["Web Browser"]
        Dozzle["Dozzle (Log Viewer: 8080)"]
    end

    subgraph "External Network (bridge)"
        IngressProxy["Ingress Proxy (Nginx)"]
        EgressProxy["Egress Proxy (Squid)"]
        ControlPanel["Control Panel"]
    end

    subgraph "Internal Network (internal: true)"
        GooseAgent["Goose Agent Container"]
        OpenCodeAgent["OpenCode Agent Container"]
        ReportWatcher["Report Watcher"]
    end

    Browser -->|HTTP 6080/6081| IngressProxy
    Browser -->|HTTP 6080/control| ControlPanel
    IngressProxy -->|WebSocket/HTTP 中継| GooseAgent
    IngressProxy -->|WebSocket/HTTP 中継| OpenCodeAgent

    GooseAgent -->|HTTP_PROXY: 3128| EgressProxy
    OpenCodeAgent -->|HTTP_PROXY: 3128| EgressProxy

    EgressProxy -->|HTTPS CONNECT (Whitelist)| Internet((Internet))
    ControlPanel -->|更新/再起動| EgressProxy
```

## 1. Docker `internal: true` ネットワーク

エージェントが実行されるコンテナ群（`goose-agent`, `opencode-agent`）は、Docker Compose で定義された `internal-net` にのみ所属します。

```yaml
networks:
  internal-net:
    driver: bridge
    internal: true
```

### 仕様と保証事項
- `internal: true` オプションにより、このネットワークには**デフォルトゲートウェイが存在しません**。
- コンテナ内から外部 IP アドレスやドメインに直接接続を試みた場合、Linux カーネルのルーティングレベルで即座に `Network is unreachable` として破棄されます。
- これにより、エージェントが独自のプロキシクライアントを使用したり、設定を無視して直接通信を行おうとする試みを根本から遮断します。

## 2. プロキシコンテナの境界線

外部（インターネットやホスト）と通信できるのは、`internal-net` と `external-net` の両方に所属している以下のプロキシコンテナのみです。

- **`egress-proxy` (Squid)**: エージェントからの外向き通信を審査し、許可されたドメインへのみ中継する。
- **`ingress-proxy` (Nginx)**: ホスト側からの内向き通信（ブラウザ画面の描画や ACP プロトコル）を中継する。

エージェントコンテナはこれらのプロキシとしか通信できず、プロキシ自体は非特権ユーザー環境（コンテナ内）で最小限の機能のみを実行するよう制限されています。

## セキュリティの限界 (スコープ外事項)
本システムはネットワーク分離に特化しており、以下の脅威モデルには対応していません（設計上のトレードオフ）。
- **コンテナエスケープ**: Linux カーネルの脆弱性 (ゼロデイなど) を突いた、ホスト OS への脱出攻撃。
- **SSL Bump (DPI)**: 暗号化された HTTPS 通信ペイロードの傍受・検査（個人情報漏洩の検査など）。本環境では宛先ドメイン単位 (CONNECT メソッド) の制御のみを行います。
