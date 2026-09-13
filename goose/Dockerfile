# goose/Dockerfile
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8

# 0. uv / uvx のマルチステージコピー（高速・安全・決定論的）
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# 1. 基本ツール + GUI/noVNC + 日本語入力 + 開発ランタイム/MCPツールのインストール
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    wget \
    ca-certificates \
    git \
    bzip2 \
    unzip \
    zip \
    patch \
    procps \
    htop \
    jq \
    ripgrep \
    tree \
    nano \
    less \
    zenity \
    # ビルドツール
    build-essential \
    # 言語ランタイム & パッケージマネージャ (Python / Node.js / MCP)
    python3 \
    python3-pip \
    python3-venv \
    pipx \
    nodejs \
    npm \
    # ターミナルマルチプレクサ (セッション・バックグラウンド管理)
    tmux \
    # GUI デスクトップ環境 (Xfce4 + Xvfb + D-Bus)
    xvfb \
    xfce4 \
    xfce4-terminal \
    dbus-x11 \
    dbus \
    # VNC & Webブラウザ接続 (noVNC)
    x11vnc \
    novnc \
    websockify \
    # 日本語フォント
    fonts-noto-cjk \
    fonts-noto-color-emoji \
    # 日本語入力システム (Fcitx5 + Mozc)
    fcitx5 \
    fcitx5-mozc \
    fcitx5-frontend-gtk2 \
    fcitx5-frontend-gtk3 \
    fcitx5-frontend-qt5 \
    && rm -rf /var/lib/apt/lists/*

# 2. 公式 Goose Desktop GUI (.deb) のインストール + --no-sandbox ラッパーの設置
ARG GOOSE_VERSION=1.50.0
RUN curl -fsSL "https://github.com/block/goose/releases/download/v${GOOSE_VERSION}/goose_${GOOSE_VERSION}_amd64.deb" -o /tmp/goose.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends /tmp/goose.deb \
    && rm -f /tmp/goose.deb \
    && rm -rf /var/lib/apt/lists/* \
    && if [ -f /usr/lib/goose/Goose ]; then \
         mv /usr/lib/goose/Goose /usr/lib/goose/Goose.real \
         && printf '#!/bin/bash\nexport GTK_IM_MODULE=fcitx\nexport QT_IM_MODULE=fcitx\nexport XMODIFIERS=@im=fcitx\nexec /usr/lib/goose/Goose.real --no-sandbox --enable-features=UseOzonePlatform --ozone-platform=x11 --enable-wayland-ime "$@"\n' > /usr/lib/goose/Goose \
         && chmod +x /usr/lib/goose/Goose; \
       fi \
     && if [ -f /usr/lib/goose/resources/bin/goose ]; then \
          ln -sf /usr/lib/goose/resources/bin/goose /usr/local/bin/goose \
          && ln -sf /usr/lib/goose/Goose /usr/local/bin/goose-desktop; \
        fi

# 3. 非rootユーザーの作成（UID/GIDはdocker-compose.ymlで上書き可能）
RUN groupadd -g 1000 sandboxuser \
    && useradd -m -u 1000 -g sandboxuser -s /bin/bash sandboxuser \
    && mkdir -p /home/sandboxuser/.config/goose /home/sandboxuser/Desktop /home/sandboxuser/.config/fcitx5 /workspace /home/sandboxuser/.local/share/goose/sessions /home/sandboxuser/.local/state/goose/logs \
    && chown -R sandboxuser:sandboxuser /home/sandboxuser /workspace

# 4. デスクトップアイコン、Fcitx5、Git、tmux 初期プロファイル設定
RUN if [ -f /usr/share/applications/goose.desktop ]; then \
        cp /usr/share/applications/goose.desktop /home/sandboxuser/Desktop/; \
        sed -i 's|Exec=/usr/lib/goose/Goose %U|Exec=/usr/lib/goose/Goose --no-sandbox %U|g' /home/sandboxuser/Desktop/goose.desktop; \
        chmod +x /home/sandboxuser/Desktop/goose.desktop; \
    fi \
    && printf "[Groups/0]\nName=Default\nDefault Layout=jp\nDefaultIM=mozc\n\n[Groups/0/Items/0]\nName=keyboard-jp\nLayout=\n\n[Groups/0/Items/1]\nName=mozc\nLayout=\n\n[GroupOrder]\n0=Default\n" > /home/sandboxuser/.config/fcitx5/profile \
    && printf "set -g mouse on\nset -g default-terminal \"screen-256color\"\nset -s escape-time 0\n" > /home/sandboxuser/.tmux.conf \
    && su - sandboxuser -c "git config --global user.name 'Goose Agent' \
        && git config --global user.email 'goose@sandbox.local' \
        && git config --global --add safe.directory /workspace \
        && git config --global init.defaultBranch main" \
    && chown -R sandboxuser:sandboxuser /home/sandboxuser/.config /home/sandboxuser/Desktop /home/sandboxuser/.tmux.conf /home/sandboxuser/.gitconfig

# 5. 実行スクリプトのコピー
COPY bin/test-egress.sh /bin/test-egress.sh
COPY bin/start-goose.sh /bin/start-goose.sh
COPY bin/start-desktop.sh /bin/start-desktop.sh
RUN chmod +x /bin/test-egress.sh /bin/start-goose.sh /bin/start-desktop.sh


# 非rootユーザーに切り替え
USER sandboxuser
WORKDIR /workspace

CMD ["/bin/bash"]
