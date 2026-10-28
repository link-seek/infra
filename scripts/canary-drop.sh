#!/bin/bash
# canary-drop.sh — 共用的 canary 丢弃函数；旧容器不动。
# 输入 env：REMOTE_DIR、CANARY_PROJECT、CANARY_CONTAINER（deploy.manifest 参数）。
set -euo pipefail
: "${REMOTE_DIR:?REMOTE_DIR required}"
: "${CANARY_PROJECT:?CANARY_PROJECT required}"
cd "$REMOTE_DIR"
if [ -n "${CANARY_CONTAINER:-}" ]; then
  docker logs "$CANARY_CONTAINER" --tail 60 2>/dev/null || true
fi
if [ -f /tmp/canary-override.yml ]; then
  docker compose -p "$CANARY_PROJECT" -f "$REMOTE_DIR/compose.yml" -f /tmp/canary-override.yml down 2>/dev/null || true
fi
docker compose -p "$CANARY_PROJECT" down 2>/dev/null || true
if [ -n "${CANARY_CONTAINER:-}" ]; then
  docker rm -f "$CANARY_CONTAINER" 2>/dev/null || true
fi
echo "canary dropped"
