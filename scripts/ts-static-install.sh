#!/bin/sh
# 新机器静态安装 tailscale（给 install.sh 不认的发行版用，如 EulerOS/HCE）。
# 用法：ts-static-install.sh <AUTHKEY> [HOSTNAME]
# 约定：persistent 节点（ephemeral=false 的 key），state 落盘，内核态。
#
# 前置 DNS（根因，2026-11-12 实测钉死）：
# tailscaled 会下发 ts-input ... -s 100.64.0.0/10 ! -i tailscale0 -j DROP（标准防 spoof），
# 而华为内网 DNS（100.125.x.x）正好落在这个段里 → up 之后 DNS 回包全吃，出网全挂。
# HW21 天生免疫（它的 resolv.conf 走 tailnet quad-100）。本脚本先把 DNS 切公网再装。
set -euo pipefail
AUTHKEY="${1:?AUTHKEY required}"
HOSTNAME="${2:-mesh-hw-41}"

# 0. DNS 切公网（NM 持久化，DHCP 不许覆盖；没 NM 就直写 resolv.conf）
if command -v nmcli >/dev/null 2>&1; then
  DEV="$(ip route show default | head -1 | grep -oE 'dev [^ ]+' | cut -d' ' -f2)"
  CONN="$(nmcli -t -f NAME,DEVICE connection show 2>/dev/null | grep ":${DEV}$" | head -1 | cut -d: -f1)"
  if [ -n "$CONN" ]; then
    nmcli connection modify "$CONN" ipv4.ignore-auto-dns yes ipv4.dns "114.114.114.114,8.8.8.8"
  fi
fi
# 直写立即生效（不做 connection up，避免 live 机闪断；NM 持久化靠上面那行）
printf 'nameserver 114.114.114.114\nnameserver 8.8.8.8\n' > /etc/resolv.conf
getent hosts pkgs.tailscale.com >/dev/null || { echo "FAIL: DNS 仍不通"; exit 1; }

# 1. 取最新静态包并安装
cd /tmp
TGZ="$(curl -fsSL https://pkgs.tailscale.com/stable/ | grep -oE 'tailscale_[0-9]+[.][0-9]+[.][0-9]+_amd64[.]tgz' | sort -uV | tail -1)"
[ -n "$TGZ" ] || { echo "FAIL: 静态包 discovery 为空"; exit 1; }
echo "static build: $TGZ"
curl -fsSL -o ts.tgz "https://pkgs.tailscale.com/stable/$TGZ"
rm -rf tailscale_*_amd64
tar xzf ts.tgz
D="$(ls -d tailscale_*_amd64 | head -1)"
# 运行中的二进制不可覆盖：先停服再拷（幂等重跑必需）。
systemctl stop tailscaled 2>/dev/null || true
cp "$D/tailscaled" "$D/tailscale" /usr/local/bin/
mkdir -p /var/lib/tailscale
printf '[Unit]\nDescription=Tailscale node agent\nAfter=network-online.target\nWants=network-online.target\n[Service]\nExecStart=/usr/local/bin/tailscaled --state=/var/lib/tailscale/tailscaled.state\nRestart=on-failure\n[Install]\nWantedBy=multi-user.target\n' > /etc/systemd/system/tailscaled.service
systemctl daemon-reload
systemctl enable --now tailscaled
sleep 3

# 2. 上线并双重验证（网内 IP + 出网不断）
tailscale up --authkey="$AUTHKEY" --hostname="$HOSTNAME" --ssh --accept-routes=false --accept-dns=false
tailscale ip -4
curl -fsSL -m 15 -o /dev/null https://pkgs.tailscale.com/stable/ \
  || { echo "FAIL: up 之后出网断了"; exit 1; }
echo "JOIN-OK: 网内+出网双通"
