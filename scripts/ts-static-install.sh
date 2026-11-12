#!/bin/sh
# 新机器静态安装 tailscale（给 install.sh 不认的发行版用，如 EulerOS/HCE）。
# 用法：ts-static-install.sh <AUTHKEY> [HOSTNAME]
# 约定：persistent 节点（ephemeral=false 的 key），state 落盘。
# 模式固定 userspace（--tun=userspace-networking）：HCE 2.0 上内核态 tailscaled
# 会劫持本机出网（实测：static 内核态一起 curl 即 000，停掉恢复 200），userspace 零侵入。
# k3s pod 内一直是这个模式；41 做管理口够用（flannel/etcd 走 tailscale0 照常）。
set -euo pipefail
AUTHKEY="${1:?AUTHKEY required}"
HOSTNAME="${2:-mesh-hw-41}"
cd /tmp
TGZ="$(curl -fsSL https://pkgs.tailscale.com/stable/ | grep -oE 'tailscale_[0-9]+[.][0-9]+[.][0-9]+_amd64[.]tgz' | sort -uV | tail -1)"
[ -n "$TGZ" ] || { echo "FAIL: 静态包 discovery 为空"; exit 1; }
echo "static build: $TGZ"
curl -fsSL -o ts.tgz "https://pkgs.tailscale.com/stable/$TGZ"
rm -rf tailscale_*_amd64
tar xzf ts.tgz
D="$(ls -d tailscale_*_amd64 | head -1)"
cp "$D/tailscaled" "$D/tailscale" /usr/local/bin/
mkdir -p /var/lib/tailscale
printf '[Unit]\nDescription=Tailscale node agent\nAfter=network-online.target\nWants=network-online.target\n[Service]\nExecStart=/usr/local/bin/tailscaled --tun=userspace-networking --state=/var/lib/tailscale/tailscaled.state\nRestart=on-failure\n[Install]\nWantedBy=multi-user.target\n' > /etc/systemd/system/tailscaled.service
systemctl daemon-reload
systemctl enable --now tailscaled
sleep 3
tailscale up --tun=userspace-networking --authkey="$AUTHKEY" --hostname="$HOSTNAME" --ssh --accept-routes=false --accept-dns=false
tailscale ip -4
