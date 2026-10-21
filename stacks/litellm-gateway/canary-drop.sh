#!/bin/bash
# canary-drop.sh — 探针失败时丢弃 canary，旧容器不动。
# 输入 env：REMOTE_DIR（未用，仅满足接口统一）。
set -euo pipefail
docker logs litellm-guard-canary --tail 60 || true
docker rm -f litellm-guard-canary || true
echo "canary dropped"
