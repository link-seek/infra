#!/bin/bash
# canary-drop.sh — 探针失败时丢弃 canary，旧容器不动。
# canary 是独立 compose 项目（-p litellm-guard-canary，自有网络），down 只拆自己的，
# 碰不到生产网络（具名 litellm-guard_default 不在 override 里）。
# 输入 env：REMOTE_DIR（compose.yml 位置）。
set -euo pipefail
docker logs litellm-guard-canary --tail 60 2>/dev/null || true
if [ -f /tmp/canary-override.yml ]; then
  docker compose -p litellm-guard-canary -f "${REMOTE_DIR:-/root/stacks/litellm-gateway}/compose.yml" -f /tmp/canary-override.yml down 2>/dev/null || true
fi
docker rm -f litellm-guard-canary 2>/dev/null || true
echo "canary dropped"
