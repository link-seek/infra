#!/bin/bash
# canary-drop.sh — 探针失败时丢弃 canary project，旧容器不动。
set -euo pipefail
cd "$REMOTE_DIR"
docker compose -p opencode-prod-canary logs --tail 60 opencode-prod 2>/dev/null || true
docker compose -p opencode-prod-canary down 2>/dev/null || true
echo "canary dropped"
