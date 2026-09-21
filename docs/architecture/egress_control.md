---
type: "architecture"
title: "Egress 通信制御とプロキシキルスイッチ"
description: "Squid を用いた Egress（外向き）通信のホワイトリスト制御、CONNECT 監査、および緊急キルスイッチの仕組み"
generated: { by: "jules/1.0", at: "2026-09-21T10:40:00Z" }
verified:
  - { by: "human:nobuhiko", at: "2026-09-21T10:45:00Z" }
status: "stable"
tags: ["squid", "egress", "proxy", "security", "whitelist"]
---

# Egress 通信制御とプロキシキルスイッチ

`egress-proxy` コンテナ (Squid) は、エージェントコンテナからのすべての外向き通信を傍受・監査し、許可されたドメイン（ホワイトリスト）への通信のみを通過させる「関所」として機能します。

## HTTP CONNECT と監査の限界

本システムでは、プライバシーと開発体験（SSL ピンニングによるエラー回避など）を重視し、**SSL Bump (DPI) によるペイロード復号は行いません**。
代わりに、HTTP `CONNECT` メソッドによるトンネル確立要求を監査し、「どのドメインに」「どれだけのデータ量を」通信したかを記録します。

- **取得できる情報**: 宛先ドメイン、ポート、転送バイト数、接続時間
- **取得できない情報**: HTTPS 通信の中身（パス、クエリパラメータ、レスポンス本文）

## ホワイトリスト ACL (Access Control List)

ホワイトリストは `squid/whitelist.txt` で管理されます。
許可したいドメインを1行ずつ記述します。正規表現や先頭ドット (`.github.com`) によるサブドメイン指定が可能です。

```squid
# squid.conf
acl allowed_domains dstdomain "/etc/squid/whitelist.txt"
http_access allow localnet allowed_domains
http_access deny all
```

**内部ルーティングの例外**
`host.docker.internal` (ホストマシン) への通信は、ローカルLLM (Ollama) 用の特定ポート (11434) のみに制限する専用 ACL が設定されています。

## 緊急キルスイッチ (Kill Switch)

AI エージェントが暴走したり、予期せぬ通信を大量に発生させたりした場合、通信を即座に物理遮断するキルスイッチ機能があります。

### 仕組み
`make block-all` を実行すると、以下の処理が行われます。
1. 現在の `whitelist.txt` を `.whitelist.txt.bak` にバックアップする。
2. `whitelist.txt` を空にする（または無効化マーカーを書き込む）。
3. `docker compose exec egress-proxy squid -k reconfigure` を発行し、Squid の設定をダウンタイムなしで即時リロードする。

これにより、既存のコネクションは切断され、以降のすべての通信が `403 Forbidden` となります。
復旧は `make unblock` を実行することで、バックアップからリストを復元し再リロードします。

## 構造化監査ログ (`json_audit`)

Squid のアクセスログは、集計や LLM による解釈を容易にするため、ISO8601 タイムスタンプと共に出力されます。

```squid
logformat json_audit escape=json {"time":"%{%Y-%m-%dT%H:%M:%S%z}tg", "client_ip":"%>a", "method":"%rm", "url":"%ru", "status":"%>Hs", "bytes":%<st, "duration":%tr, "user_agent":"%{User-Agent}>h", "content_type":"%{Content-Type}>h", "referer":"%{Referer}>h"}
access_log /var/log/squid/access.json json_audit !healthcheck_src
```

※ HTTP CONNECT トンネルの場合、`user_agent` などのヘッダーは取得できないため `-` となります。
