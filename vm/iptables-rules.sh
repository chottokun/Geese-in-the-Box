#!/bin/bash
# ==========================================
# iptables 外部通信遮断ルール
# ==========================================
# Squid プロセス (uid: proxy) のみが外部通信を許可される。
# それ以外のプロセスからの外部向けパケットはカーネルレベルで DROP。
# VM 起動時に root 権限で実行すること。
set -euo pipefail

echo "=== iptables 外部通信遮断ルールを適用中 ==="

# 既存ルールをクリア
iptables -F OUTPUT
iptables -F INPUT

# OUTPUT ポリシー: デフォルト DROP
iptables -P OUTPUT DROP

# INPUT ポリシー: デフォルト DROP（必要なポートのみ許可）
iptables -P INPUT DROP

# --- OUTPUT ルール ---

# ループバック許可
iptables -A OUTPUT -o lo -j ACCEPT

# 確立済みセッションの応答許可
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Squid プロセス (uid: proxy) のみ外部通信を許可
iptables -A OUTPUT -m owner --uid-owner proxy -p tcp --dport 443 -j ACCEPT
iptables -A OUTPUT -m owner --uid-owner proxy -p tcp --dport 80 -j ACCEPT
iptables -A OUTPUT -m owner --uid-owner proxy -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -m owner --uid-owner proxy -p tcp --dport 53 -j ACCEPT

# --- INPUT ルール ---

# ループバック許可
iptables -A INPUT -i lo -j ACCEPT

# 確立済みセッションの応答許可
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# SSH 受信許可（Multipass 管理用）
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# RDP 受信許可（GUI デスクトップ接続）
iptables -A INPUT -p tcp --dport 3389 -j ACCEPT

# VNC 受信許可（GUI デスクトップ接続）
iptables -A INPUT -p tcp --dport 5900 -j ACCEPT

# GoAccess ダッシュボード受信許可
iptables -A INPUT -p tcp --dport 7890 -j ACCEPT

echo "=== iptables ルール適用完了 ==="
echo ""
echo "確認:"
echo "  - Squid (uid: proxy) のみ外部 HTTP/HTTPS/DNS を送信可能"
echo "  - その他のプロセスからの外部通信は全 DROP"
echo "  - SSH/RDP/VNC/GoAccess の受信のみ許可"
echo ""
iptables -L -n --line-numbers
