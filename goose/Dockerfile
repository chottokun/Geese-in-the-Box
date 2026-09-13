# goose/Dockerfile
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    git \
    bzip2 \
    procps \
    jq \
    ripgrep \
    && rm -rf /var/lib/apt/lists/*

# 非rootユーザーの作成（UID/GIDはdocker-compose.ymlで上書き可能）
RUN groupadd -g 1000 sandboxuser \
    && useradd -m -u 1000 -g sandboxuser sandboxuser \
    && mkdir -p /home/sandboxuser/.config/goose /workspace \
    && chown -R sandboxuser:sandboxuser /home/sandboxuser /workspace

# Goose CLI のインストール（対話的設定をスキップし、システム全体パスへ直接導入）
RUN curl -fsSL https://github.com/block/goose/releases/download/stable/download_cli.sh -o /tmp/download_cli.sh \
    && CONFIGURE=false GOOSE_BIN_DIR=/usr/local/bin bash /tmp/download_cli.sh \
    && rm /tmp/download_cli.sh

# 実行スクリプトのコピー
COPY bin/test-egress.sh /bin/test-egress.sh
COPY bin/start-goose.sh /bin/start-goose.sh
RUN chmod +x /bin/test-egress.sh /bin/start-goose.sh

# 非rootユーザーに切り替え
USER sandboxuser
WORKDIR /workspace

CMD ["/bin/bash"]
