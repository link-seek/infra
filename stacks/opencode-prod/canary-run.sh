#!/bin/bash
# canary-run.sh — 独立 compose project 起 canary（同镜像同 env 内容，同类网络，换端口防冲突）。
# 输入 env：REMOTE_DIR、CANDIDATE_DIGEST、CANARY_PORT、CANARY_BROWSER_PORT（manifest 同名变量由复用线 export）。
set -euo pipefail
cd "$REMOTE_DIR"
CANARY_PORT="${CANARY_PORT:-14097}"
CANARY_BROWSER_PORT="${CANARY_BROWSER_PORT:-19228}"
docker compose -p opencode-prod-canary down 2>/dev/null || true
NEW_IMG="$(grep 'image:' compose.yml | grep opencode-tools | head -1 | sed 's/.*image: *//')"
echo "canary image: $NEW_IMG (want $CANDIDATE_DIGEST)"
# 干净机（如 img 预检 runner）无 registry 凭证时先登录；有则复用宿主已有凭证
if [ -n "${SWR_USER:-}" ]; then
  REG="${NEW_IMG%%/*}"
  case "$REG" in *.*) printf '%s' "${SWR_PASS:-}" | docker login "$REG" -u "$SWR_USER" --password-stdin;; esac
fi
docker pull "$NEW_IMG"
# 端口/container_name 覆盖（源 compose 写死 4097 与固定容器名，canary 必须错开）
cat > /tmp/canary-override.yml <<EOF
services:
  opencode-prod:
    container_name: opencode-prod-canary
    # .env 里 BROWSER_CDP_URL 指向生产 browser（172.17.0.1:9222），environment 优先级高于 env_file，
    # 必须改指 canary 自己的映射，否则会静默连到生产浏览器（干净机上则无人监听）。
    environment:
      BROWSER_CDP_URL: "http://172.17.0.1:$CANARY_BROWSER_PORT"
    # !override：ports 默认是累加合并，不加这个底包的宿主绑定会漏进 canary，
    # 生产机上直接撞车（hw-21 Compose v2.27.1，门槛 2.24.4，2026-10-26 实测）。
    # canary 仍走 compose up，真源仍是 compose.yml，不分叉。
    ports: !override
      - "$CANARY_PORT:4097"
  browser:
    container_name: opencode-browser-canary
    # 换宿主端口并把 docker0 网关绑定带上：容器内 headless-shell 只认 IP Host 头，
    # 必须能经 172.17.0.1:<canary port> 连到 canary 浏览器，不能复用生产 9222。
    ports: !override
      - "127.0.0.1:$CANARY_BROWSER_PORT:9222"
      - "172.17.0.1:$CANARY_BROWSER_PORT:9222"
EOF
docker compose -p opencode-prod-canary -f compose.yml -f /tmp/canary-override.yml up -d opencode-prod browser
echo "canary started on :$CANARY_PORT"
