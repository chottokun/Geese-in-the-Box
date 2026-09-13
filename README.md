# Goose-in-the-Box: AI エージェント完全通信制御＆監査サンドボックス

AIエージェント「Goose」を安全に実行するための、Dockerベースの通信完全隔離・監査サンドボックスです。

Docker の `internal: true` ネットワーク（L3/L4）と Squid フォワードプロキシ（L7）の **2段構え** により、エージェントによる勝手な外部通信やデータ流出を 100% 遮断し、全通信試行を構造化 JSON ログに記録・監査します。また、Goose 本体の匿名テレメトリ送信もデフォルトで無効化されています。

---

## 主な特徴

- 🔒 **プロキシバイパスの完全排除 (L3/L4 隔離)**:
  - エージェントコンテナは `internal: true` ネットワーク内に配置され、外部へのデフォルトゲートウェイが存在しません。
  - プロキシ設定を無視した直接通信（IP直撃やDNS漏洩）を試みても、Linux カーネルが即座にパケットを破棄します。
- 🛡️ **厳格なホワイトリスト制御 (L7 制御)**:
  - 外部と通信可能な唯一の出口である Squid プロキシが、`whitelist.txt` に登録されたドメイン宛てのみ通過を許可します。未許可ドメインは `403 Forbidden` で即座に遮断されます。
- 📊 **JSON 構造化監査ログ**:
  - 全通信（許可・遮断・HTTPステータス・ドメイン・送受信量）を ISO8601 タイムスタンプ付きの JSON 形式で `/var/log/squid/access.json` に記録。CLI で即座にフィルタリング・集計が可能です。
- 🚫 **テレメトリ強制遮断**:
  - `GOOSE_TELEMETRY_ENABLED=false` が適用され、エージェント自体の利用データ送信を抑止します。

---

## ファイル構成

```text
goose-in-the-box/
├── docker-compose.yml       # 内部隔離(internal-net)と外部プロキシ(external-net)の定義
├── Makefile                 # ビルド、テスト、セッション起動、監査集計ワンライナー
├── README.md                # 本ドキュメント
├── .env.example             # LLMプロバイダー用APIキーテンプレート
├── squid/
│   ├── squid.conf           # 厳格なフォワードプロキシ設定 + JSON構造化監査ログ定義
│   └── whitelist.txt        # 許可ドメイン一覧（OpenAI, Anthropic, Gemini, GitHub等）
├── nginx/
│   └── nginx.conf           # Ingressリバースプロキシ設定 (noVNC WebSocket / ACP中継)
├── goose/
│   └── Dockerfile           # Goose CLI + Xfce4/noVNC/D-Busを導入した隔離コンテナ
├── bin/
│   ├── test-egress.sh       # 通信遮断・プロキシ迂回防止・監査ログの自動検証スクリプト
│   └── start-goose.sh       # AGENTS.md / ルール自動結合とGoose対話セッション起動
├── workspace/               # Goose作業ディレクトリ（ホストとマウント）
│   ├── AGENTS.md            # 作業ルール・セキュリティガイドライン
│   └── .agents/             # スキルや分割ルールの配置場所
├── logs/                    # Squid 監査ログ出力先（ホストから閲覧可能）
│   └── squid/
│       ├── access.json      # JSON 構造化監査ログ
│       └── access.log       # テキスト形式ログ
└── plan/
    └── implementation_plan.md # 実装計画書 (v3)
```

## 設定パラメータ (.env)

環境設定はすべて `.env` ファイルで一元管理できます（`.env.example` を参考に設定）。

| パラメータ | 説明 | デフォルト値 |
| :--- | :--- | :--- |
| **`OPENAI_API_KEY` 等** | 各種 LLM プロバイダーの API キー | （空欄） |
| **`OLLAMA_HOST`** | ローカル LLM ホスト接続先 | `http://host.docker.internal:11434` |
| **`NOVNC_PORT`** | noVNC Web UI ポート（ブラウザ接続先） | `6080` |
| **`GOOSE_SERVE_PORT`** | Goose ACP サーバー公開ポート | `3284` |
| **`SQUID_PORT`** | Squid 監査プロキシポート | `3128` |
| **`DOZZLE_PORT`** | Dozzle Web リアルタイムログ監視ポート | `8080` |
| **`RESOLUTION`** | 仮想デスクトップ解像度 | `1280x800x24` |
| **`TZ`** | タイムゾーン（時計・ログ出力時刻） | `Asia/Tokyo` |
| **`SHM_SIZE`** | 共有メモリサイズ（GUI安定化用） | `1gb` |
| **`UID` / `GID`** | コンテナ内実行ユーザー権限 | `1000` / `1000` |
| **`GOOSE_TELEMETRY_ENABLED`** | 匿名の利用実績データ送信制御 | `false` |

---

## クイックスタート

### 1. 初期設定
```bash
cp .env.example .env
# .env を開いて必要な API キーや設定を調整
```

### 2. コンテナイメージのビルド
```bash
make build
```

### 3. 通信遮断の実動テスト
隔離環境内から検証スクリプトを実行し、通信制御が正常に働いているかテストします：
```bash
make test
```
**テスト内容:**
1. ✅ **ホワイトリストドメイン (`api.openai.com`)**: プロキシ経由で正常に接続
2. 🛑 **非許可ドメイン (`www.google.com`)**: Squid プロキシが `403 Forbidden` で遮断
3. 🔒 **直接接続バイパス**: Docker `internal: true` により `Network unreachable` で遮断

---

## Goose の実行

### CLI 対話セッション
`workspace/AGENTS.md` や `.agents/rules/*.md` のルールを自動読み込みし、隔離環境内で Goose CLI を開始します：
```bash
make session
```

### Goose Desktop（GUI）との連携
ACP サーバーを起動し、ホスト側の Goose Desktop から接続して作業します：
```bash
make serve
```
* ホスト側 Goose Desktop の接続先: `http://localhost:3284`

### コンテナ内 GUI デスクトップの利用 (noVNC / ブラウザ操作)
エージェントにブラウザを操作させたり、コンテナ内の画面を丸ごと確認・操作したい場合は、GUI デスクトップ環境を起動します：
```bash
make gui
```
* 起動後、ホストのブラウザで **`http://localhost:6080/vnc.html`** を開くと、隔離コンテナ内の Xfce4 デスクトップがそのままブラウザ上に表示されます。
* VNC クライアントから接続する場合は `localhost:5900` にアクセスします。

---

## 通信ログの監査・分析

### Dozzle によるリアルタイムWebログ監視
Dozzle が `docker-compose.yml` に定義されており、ブラウザからコンテナのログをリアルタイムに確認・検索・フィルタリングできます：
* **http://localhost:8080** にアクセス
* `egress-proxy` コンテナを選択することで、Squid のアクセスログ（`TCP_TUNNEL/200` や `TCP_DENIED/403` など）を色分け・フィルタ監視可能です。

### CLI でのリアルタイム監査ログの閲覧
```bash
make logs
```

### 遮断された通信 (403 DENIED) の一覧抽出
エージェントがアクセスを試みてブロックされたドメインや URL を確認します：
```bash
make audit-denied
```

### 宛先ドメイン別アクセス頻度集計
```bash
make audit-summary
```

---

## ドメインホワイトリストの動的制御 & 完全キルスイッチ

### ドメインの動的オン/オフ (リロード)
許可するドメインを追加・変更したい場合は、ホスト側の `squid/whitelist.txt` を編集後、以下のコマンドで Squid の設定を即時反映します：
```bash
# squid/whitelist.txt を編集後に実行
make reload
```
*(通信を切断・再接続することなく即時にホワイトリスト変更が適用されます)*

### 完全キルスイッチ（一括オン/オフ）
緊急時などに CLI から全通信を瞬時にシャットダウン・復元できます：
```bash
# 全通信を緊急遮断（ホワイトリストを空にして reconfigure）
make block-all

# 通信遮断を解除（ホワイトリストを復元して reconfigure）
make unblock
```
