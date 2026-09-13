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

# Goose CLI のインストール（rootで実行し、全ユーザーで利用可能にする）
RUN curl -fsSL https://github.com/block/goose/releases/download/stable/download_cli.sh | bash \
    && cp -r /root/.local/bin/goose /usr/local/bin/ 2>/dev/null || true

# テストスクリプトのコピー
COPY bin/test-egress.sh /bin/test-egress.sh
RUN chmod +x /bin/test-egress.sh

# 非rootユーザーに切り替え
USER sandboxuser
WORKDIR /workspace

ENTRYPOINT ["/bin/bash"]
