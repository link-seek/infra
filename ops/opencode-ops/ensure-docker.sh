#!/usr/bin/env bash
# ensure-docker.sh —— 幂等安装 docker-ce（华为镜像站，el8；现代版支持 cgroup v2）+ compose 插件。
# 说明：HW21 是 HCE 2.0（glibc 2.34，openEuler 22.03 血统），HCE 自带 docker-engine 18.09 不支持 cgroup v2，
#       故走华为 docker-ce 镜像站的 el8 源（实测依赖仅 HCE 自带 container-selinux/libcgroup）。
#       与 k3s 共存：daemon.json 关 iptables/ip-forward/bridge；容器用 --network host。
set -euo pipefail

if ! docker --version >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
  echo ">>> 安装 docker-ce（华为镜像站 el8 源）"
  curl -fsSL -o /etc/yum.repos.d/docker-ce.repo \
    https://repo.huaweicloud.com/docker-ce/linux/centos/docker-ce.repo || true
  # 若源文件不可用则直接内联 baseurl（更稳）
  cat > /etc/yum.repos.d/docker-ce.repo <<'EOF'
[docker-ce-stable]
name=Docker CE Stable - Huawei mirror (el8)
baseurl=https://repo.huaweicloud.com/docker-ce/linux/centos/8/x86_64/stable/
enabled=1
gpgcheck=0
EOF
  dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

install -d -m 755 /etc/docker
if [ ! -f /etc/docker/daemon.json ]; then
  cat > /etc/docker/daemon.json <<'EOF'
{
  "iptables": false,
  "ip-forward": false,
  "bridge": "none"
}
EOF
fi
systemctl enable --now docker
# 让 daemon.json 生效（已运行则重启）
systemctl restart docker
docker --version
docker compose version
