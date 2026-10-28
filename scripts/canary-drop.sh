#!/usr/bin/env bash
# canary-drop.sh — 共用 canary 丢弃器（唯一真相）；只拆 canary 自己的 compose 项目，旧容器不动。
# 输入 env：REMOTE_DIR（栈目录）。参数（manifest）：CANARY_PROJECT、CANARY_SERVICE、CANARY_CONTAINER。
set -euo pipefail
: "${REMOTE_DIR:?REMOTE_DIR required}"
REQUESTED_REMOTE_DIR="$REMOTE_DIR"
# shellcheck disable=SC1090,SC1091
source "$REMOTE_DIR/deploy.manifest"
REMOTE_DIR="$REQUESTED_REMOTE_DIR"
cd "$REMOTE_DIR"

CANARY_PROJECT="${CANARY_PROJECT:?manifest 缺 CANARY_PROJECT}"
CANARY_SERVICE="${CANARY_SERVICE:-}"
CANARY_CONTAINER="${CANARY_CONTAINER:-}"
OVERRIDE_FILE="/tmp/${CANARY_PROJECT}-override.yml"

if [ -n "$CANARY_SERVICE" ]; then
  if [ -f "$OVERRIDE_FILE" ]; then
    docker compose -p "$CANARY_PROJECT" -f compose.yml -f "$OVERRIDE_FILE" logs --tail 60 "$CANARY_SERVICE" 2>/dev/null || true
  else
    docker compose -p "$CANARY_PROJECT" logs --tail 60 "$CANARY_SERVICE" 2>/dev/null || true
  fi
fi
if [ -f "$OVERRIDE_FILE" ]; then
  docker compose -p "$CANARY_PROJECT" -f compose.yml -f "$OVERRIDE_FILE" down 2>/dev/null || true
else
  docker compose -p "$CANARY_PROJECT" down 2>/dev/null || true
fi
[ -z "$CANARY_CONTAINER" ] || docker rm -f "$CANARY_CONTAINER" 2>/dev/null || true
echo "canary dropped"
