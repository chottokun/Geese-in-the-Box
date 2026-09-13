# Goose-in-the-Box: VM完全隔離 + Squid通信制御 実装計画書 (v2)

> **方針**: Docker サンドボックス構成を廃止し、VM による完全隔離に刷新する。
> Squid は VM 内のホストプロセスとして L7 通信制御・監査の中核を担う。
> 後方互換性は不要。

---

## 1. アーキテクチャ

```text
┌─────────────────────────────────────────────────────────────────┐
│  ホストマシン                                                     │
│                                                                   │
│  [Goose Desktop (RDP/VNC クライアント)] ─── RDP/VNC ────┐        │
│  [ブラウザ: 監査ダッシュボード http://localhost:7890] ──┐ │        │
│                                                         │ │        │
└─────────────────────────────────────────────────────────┼─┼────────┘
                                                          │ │
              ┌───────────────────────────────────────────┼─┼────────┐
              │ VM 境界 (OS・メモリ・FS・ネットワーク 完全隔離)       │
              │                                                       │
              │  ┌──────────────────────────────────────────────────┐ │
              │  │ iptables: Squid (port 3128) 以外の               │ │
              │  │           外部通信を全 DROP (L3/L4 強制)         │ │
              │  └──────────────────────────────────────────────────┘ │
              │                         │                             │
              │  ┌──────────────────────▼───────────────────────┐    │
              │  │ Squid (ホストプロセス, port 3128)              │    │
              │  │  ├─ ドメインホワイトリスト制御 (L7)            │    │
              │  │  ├─ JSON 構造化監査ログ                        │    │
              │  │  └─ HTTPS CONNECT ドメイン記録                 │    │
              │  └──────────────────────────────────────────────┘    │
              │                                                       │
              │  ┌─────────────────────────────────────────────────┐  │
              │  │ Goose (CLI / ACP serve)                          │  │
              │  │  ├─ 全 HTTP(S) → Squid 経由に強制               │  │
              │  │  ├─ workspace/ で作業                            │  │
              │  │  └─ テレメトリ無効 (GOOSE_TELEMETRY_ENABLED=false)│  │
              │  └─────────────────────────────────────────────────┘  │
              │                                                       │
              │  ┌─────────────────────────────────────────────────┐  │
              │  │ GoAccess (監査ダッシュボード, port 7890)         │  │◄─ ブラウザ
              │  │  └─ Squid JSON ログをリアルタイム解析            │  │
              │  └─────────────────────────────────────────────────┘  │
              │                                                       │
              │  ┌─────────────────────────────────────────────────┐  │
              │  │ GUI デスクトップ (Xfce)                          │  │◄─ RDP/VNC
              │  │  └─ Goose Desktop アプリ (オプション)            │  │
              │  └─────────────────────────────────────────────────┘  │
              └───────────────────────────────────────────────────────┘
```

### 通信制御の2段構え

| レイヤー | 手段 | 役割 |
|---------|------|------|
| **L3/L4** | iptables/nftables | Squid (port 3128) 以外の外部向けパケットを全 DROP。プロキシバイパスを物理的に不可能にする |
| **L7** | Squid | ドメイン単位のホワイトリスト制御、HTTPS CONNECT のドメイン判定、構造化監査ログ |

---

## 2. 廃止するもの（既存 Docker 構成）

以下のファイル/構成は VM 化により不要となり、削除または置き換える：

| 廃止対象 | 理由 |
|---------|------|
| `docker-compose.yml` | Docker ネットワーク隔離 → VM ネットワーク隔離に置換 |
| `goose/Dockerfile` | コンテナビルド → cloud-init プロビジョニングに置換 |
| `bin/test-egress.sh` | Docker ネットワーク前提のテスト → VM 向けに書き直し |
| `bin/start-goose.sh` | Docker 内起動スクリプト → VM 内に直接配置 |

> **重要**: 既存の `squid/squid.conf` と `squid/whitelist.txt` は、Docker 固有設定（リバースプロキシ部分、Docker ブリッジ IP レンジ）を除去した上で再利用する。ホワイトリストのドメイン一覧はそのまま引き継ぐ。

---

## 3. 成果物一覧（新規）

```text
goose-in-the-box/
├── vm/
│   ├── cloud-init.yaml          # VM 自動プロビジョニング定義
│   ├── iptables-rules.sh        # L3/L4 外部通信遮断ルール
│   └── README.md                # VM 起動・接続手順
├── squid/
│   ├── squid.conf               # 刷新: Docker固有設定を除去、JSON監査ログ追加
│   └── whitelist.txt            # 既存流用
├── goaccess/
│   └── goaccess.conf            # GoAccess 設定（JSONログパース定義）
├── bin/
│   ├── test-egress.sh           # 刷新: VM 向け通信遮断テスト
│   └── start-goose.sh           # 刷新: VM 内直接起動用
├── workspace/                   # Goose 作業ディレクトリ
│   └── AGENTS.md                # 既存流用
├── Makefile                     # 刷新: VM ライフサイクル管理コマンド
├── README.md                    # 刷新: VM ベースのクイックスタート
├── .env.example                 # 既存流用
└── plan/
    └── implementation_plan.md   # 本計画書
```

---

## 4. 実装フェーズ

### フェーズ 1: Squid 監査ログの強化

既存の `squid.conf` を VM 向けに刷新し、JSON 構造化監査ログを導入する。

#### 1.1 `squid/squid.conf` の刷新

- Docker 固有設定の削除:
  - リバースプロキシ設定（port 3284, `cache_peer goose-agent`）を全削除
  - Docker ブリッジネットワーク ACL（`localnet src 10.0.0.0/8` 等）を `localhost` + VM 内ローカルに限定
- JSON 構造化ログフォーマットの追加:
  ```
  logformat json_audit {"time":"%{%Y-%m-%dT%H:%M:%S%z}tl","client":"%>a","status":%>Hs,"squid_status":"%Ss","method":"%rm","url":"%ru","domain":"%>rd","bytes_sent":%<st,"bytes_received":%>st,"duration_ms":%tr}
  access_log /var/log/squid/access.json json_audit
  ```
- ログ出力項目: ISO8601タイムスタンプ、クライアントIP、HTTPステータス、Squidステータス（`TCP_TUNNEL`/`TCP_DENIED`）、メソッド、URL、宛先ドメイン、送受信バイト数、所要時間

#### 1.2 ログローテーション

- `logrotate` 設定を cloud-init 内で配置
- 日次ローテーション、gzip 圧縮、14世代保持

---

### フェーズ 2: VM プロビジョニング

#### 2.1 `vm/cloud-init.yaml`

Multipass + cloud-init で VM を自動構築する。cloud-init で以下をプロビジョニング：

1. **パッケージインストール**:
   - `squid`, `goaccess`, `xfce4`, `xrdp` (or `tigervnc`), `curl`, `git`, `jq`, `ripgrep`
   - Goose CLI (`download_cli.sh`)

2. **Squid 設定の配置**:
   - `squid/squid.conf` → `/etc/squid/squid.conf`
   - `squid/whitelist.txt` → `/etc/squid/whitelist.txt`
   - ログディレクトリ `/var/log/squid/` の作成

3. **システム全体のプロキシ強制設定**:
   ```bash
   # /etc/environment
   HTTP_PROXY=http://127.0.0.1:3128
   HTTPS_PROXY=http://127.0.0.1:3128
   http_proxy=http://127.0.0.1:3128
   https_proxy=http://127.0.0.1:3128
   NO_PROXY=localhost,127.0.0.1
   ```

4. **テレメトリ無効化**:
   ```bash
   GOOSE_TELEMETRY_ENABLED=false
   ```

5. **goose ユーザーの作成**:
   - 非 root ユーザー `goose` を作成
   - `workspace/` を作業ディレクトリとして配置

#### 2.2 `vm/iptables-rules.sh`

VM 起動時に適用する iptables ルール。**Squid 以外の外部通信を完全遮断**する：

```bash
#!/bin/bash
# Squid (port 3128) の OUTPUT のみ外部通信を許可
# それ以外のプロセスからの外部向けパケットは全 DROP

# ポリシー: OUTPUT はデフォルト DROP
iptables -P OUTPUT DROP

# ループバック許可
iptables -A OUTPUT -o lo -j ACCEPT

# 確立済みセッションの応答許可
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Squid プロセス (uid: proxy) のみ外部 HTTPS (443) / HTTP (80) / DNS (53) を許可
iptables -A OUTPUT -m owner --uid-owner proxy -p tcp --dport 443 -j ACCEPT
iptables -A OUTPUT -m owner --uid-owner proxy -p tcp --dport 80 -j ACCEPT
iptables -A OUTPUT -m owner --uid-owner proxy -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -m owner --uid-owner proxy -p tcp --dport 53 -j ACCEPT

# RDP/VNC 受信許可 (INPUT)
iptables -A INPUT -p tcp --dport 3389 -j ACCEPT  # RDP
iptables -A INPUT -p tcp --dport 5900 -j ACCEPT  # VNC

# GoAccess ダッシュボード受信許可 (INPUT)
iptables -A INPUT -p tcp --dport 7890 -j ACCEPT

# その他の外部向け通信は全 DROP（デフォルトポリシーで適用済み）
```

**効果**: Goose プロセスが `HTTP_PROXY` を無視して直接外部に接続しようとしても、カーネルレベルでパケットが破棄される。Squid（`proxy` UID）だけが外部と通信できる。

---

### フェーズ 3: Makefile・スクリプト・README の刷新

#### 3.1 `Makefile` の刷新

```makefile
.PHONY: vm-create vm-start vm-stop vm-destroy vm-shell vm-gui test logs audit-denied audit-summary

# VM ライフサイクル管理
vm-create:
	multipass launch --name goose-box --cloud-init vm/cloud-init.yaml --cpus 2 --memory 4G --disk 20G

vm-start:
	multipass start goose-box

vm-stop:
	multipass stop goose-box

vm-destroy:
	multipass delete goose-box && multipass purge

vm-shell:
	multipass shell goose-box

# GUI 接続
vm-gui:
	@echo "RDP: localhost:3389 / VNC: localhost:5900 に接続してください"
	@echo "Multipass VM IP: $$(multipass info goose-box | grep IPv4 | awk '{print $$2}')"

# 通信遮断テスト
test:
	multipass exec goose-box -- /opt/goose-box/bin/test-egress.sh

# 監査ログ
logs:
	multipass exec goose-box -- tail -f /var/log/squid/access.json

# 監査集計
audit-denied:
	multipass exec goose-box -- bash -c "jq -r 'select(.squid_status | test(\"DENIED\")) | [.time, .method, .domain, .url] | @tsv' /var/log/squid/access.json"

audit-summary:
	multipass exec goose-box -- bash -c "jq -r '.domain' /var/log/squid/access.json | sort | uniq -c | sort -rn | head -10"

# 監査ダッシュボード
monitor:
	@echo "ブラウザで http://$$(multipass info goose-box | grep IPv4 | awk '{print $$2}'):7890 を開いてください"
```

#### 3.2 `bin/test-egress.sh` の刷新

Docker 前提のテストを VM 向けに書き直す：
1. **ホワイトリストドメインのテスト**: `curl --proxy http://127.0.0.1:3128 https://api.openai.com` → 接続成功を確認
2. **非許可ドメインのテスト**: `curl --proxy http://127.0.0.1:3128 https://www.google.com` → 403 Forbidden を確認
3. **プロキシバイパスのテスト**: `curl --noproxy "*" --connect-timeout 3 https://api.openai.com` → 接続不可（iptables DROP）を確認
4. **監査ログ記録のテスト**: テスト後に `/var/log/squid/access.json` に JSON エントリが記録されていることを確認

#### 3.3 `README.md` の刷新

VM ベースの新しいクイックスタートに全面書き換え：
- 前提条件: Multipass のインストール
- `make vm-create` → `make test` → `make vm-gui` の 3 ステップ
- 監査ダッシュボードの利用方法
- トラブルシューティング

---

### フェーズ 4: 結合テスト・セキュリティ検証

#### 4.1 通信制御の検証

| テスト項目 | 期待結果 |
|-----------|---------|
| ホワイトリストドメインへの接続 | Squid 経由で成功 |
| 非許可ドメインへの接続 | Squid が 403 で遮断 |
| プロキシバイパス（直接接続） | iptables が DROP |
| DNS 直接解決（Squid 経由外） | iptables が DROP |

#### 4.2 監査ログの検証

| テスト項目 | 期待結果 |
|-----------|---------|
| 許可された通信の JSON ログ記録 | `access.json` に `TCP_TUNNEL` エントリ |
| 遮断された通信の JSON ログ記録 | `access.json` に `TCP_DENIED` エントリ |
| `make audit-denied` の出力 | 遮断エントリのみが一覧表示 |
| GoAccess ダッシュボードの表示 | リアルタイムでトラフィック可視化 |

#### 4.3 VM 隔離の検証

| テスト項目 | 期待結果 |
|-----------|---------|
| VM 内からホストファイルシステムへのアクセス | 不可 |
| VM 破棄後のデータ残留 | なし（`make vm-destroy`） |

---

## 5. 実装順序

フェーズ1 (squid.conf刷新) → フェーズ2 (VM プロビジョニング) → フェーズ3 (UX整備) → フェーズ4 (結合テスト)

## Open Questions

1. **VMプロビジョニングツールの選定**: Multipass を前提としていますが、Vagrant + libvirt/VirtualBox を優先する理由があれば変更可能です。Multipass は Ubuntu 公式で最も軽量に起動できますが、非 Ubuntu ゲスト OS が必要な場合は Vagrant が適しています。

2. **GUI デスクトップの要否**: Goose Desktop（GUI）を VM 内で使う場合は Xfce + RDP/VNC が必要ですが、CLI のみで運用する場合は GUI 層を省略してリソースを節約できます。どちらを優先しますか？

3. **GoAccess の配置**: VM 内にホストプロセスとして配置する案で進めていますが、ホスト側で JSON ログをマウント/転送して解析する方式も可能です。VM 内に閉じるほうがシンプルですが、ホスト側にダッシュボードがあるほうが便利な場面もあります。
