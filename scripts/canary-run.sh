#!/usr/bin/env bash
# canary-run.sh — 共用 canary 启动器（唯一真相）；栈差异只来自 deploy.manifest 参数。
# 输入 env：REMOTE_DIR（栈目录，compose/.env/deploy.manifest 已同步）、CANDIDATE_DIGEST。
# 主要参数（manifest）：CANARY_PROJECT/SERVICE(S)/CONTAINER、CANARY_PORT、CANARY_NETWORK、
#   CANARY_MASTER、CANARY_BROWSER_*、CANARY_HOSTNAME/TS_HOSTNAME、PIN_REPOS。
set -euo pipefail
: "${REMOTE_DIR:?REMOTE_DIR required}"
REQUESTED_REMOTE_DIR="$REMOTE_DIR"
# shellcheck disable=SC1090,SC1091
source "$REMOTE_DIR/deploy.manifest"
REMOTE_DIR="$REQUESTED_REMOTE_DIR"
cd "$REMOTE_DIR"

CANARY_PROJECT="${CANARY_PROJECT:?manifest 缺 CANARY_PROJECT}"
CANARY_SERVICE="${CANARY_SERVICE:?manifest 缺 CANARY_SERVICE}"
CANARY_CONTAINER="${CANARY_CONTAINER:?manifest 缺 CANARY_CONTAINER}"
CANARY_SERVICES="${CANARY_SERVICES:-$CANARY_SERVICE}"
read -r -a SERVICES <<< "$CANARY_SERVICES"

docker compose -p "$CANARY_PROJECT" down 2>/dev/null || true
IMAGE_REPO="${CANARY_IMAGE_REPO:-${PIN_REPOS:-}}"
IMAGE_REPO="${IMAGE_REPO%% *}"
if [ -n "$IMAGE_REPO" ]; then
  NEW_IMG="$(grep -E 'image:[[:space:]]*[^[:space:]]+@sha256:[0-9a-f]+' compose.yml | grep -F "$IMAGE_REPO" | head -1 | sed 's/.*image: *//' || true)"
  [ -n "$NEW_IMG" ] || { echo "FAIL: compose 里找不到 $IMAGE_REPO 的 digest pin（schema 门应已拦下）"; exit 1; }
else
  NEW_IMG="$(grep -E 'image:[[:space:]]*[^[:space:]]+@sha256:[0-9a-f]+' compose.yml | head -1 | sed 's/.*image: *//' || true)"
  [ -n "$NEW_IMG" ] || { echo "FAIL: compose 里找不到 digest pin 的 image 行（schema 门应已拦下）"; exit 1; }
fi
echo "canary image: $NEW_IMG (want ${CANDIDATE_DIGEST:-none})"

# 干净机（如 img 预检 runner）无 registry 凭证时先登录；有则复用宿主已有凭证
if [ -n "${SWR_USER:-}" ]; then
  REG="${NEW_IMG%%/*}"
  case "$REG" in *.*) printf '%s' "${SWR_PASS:-}" | docker login "$REG" -u "$SWR_USER" --password-stdin;; esac
fi
docker pull "$NEW_IMG"

# 网关类栈：canary 与切流共用同一把随机 master，切流时从 .canary_master 取回。
if [ "${CANARY_MASTER:-0}" = "1" ]; then
  LITELLM_MASTER_KEY="sk-$(openssl rand -hex 32)"
  export LITELLM_MASTER_KEY
  printf '%s' "$LITELLM_MASTER_KEY" > "$REMOTE_DIR/.canary_master"
  chmod 600 "$REMOTE_DIR/.canary_master"
fi

# override 只做隔离（容器名/端口/网络），image/env/command 全走底包 compose.yml（真源唯一）。
# ports 用 !override 而不用默认合并：底包宿主绑定漏进 canary 会在生产机撞车。
# networks 用 !override 时切到 canary 自有网络，避免挂生产网、down 时误删生产网络。
OVERRIDE_FILE="/tmp/${CANARY_PROJECT}-override.yml"
{
  printf 'services:\n'
  printf '  %s:\n' "$CANARY_SERVICE"
  printf '    container_name: %s\n' "$CANARY_CONTAINER"
  if [ -n "${CANARY_HOSTNAME:-}" ]; then
    printf '    hostname: %s\n' "$CANARY_HOSTNAME"
  fi
  if [ "${CANARY_TS_HOSTNAME:-0}" = "1" ]; then
    printf '    environment:\n'
    printf '      TS_HOSTNAME: %s\n' "${CANARY_HOSTNAME:-$CANARY_CONTAINER}"
  fi
  if [ -n "${CANARY_PORT:-}" ]; then
    printf '    ports: !override\n'
    printf '      - "%s:%s"\n' "$CANARY_PORT" "${CANARY_CONTAINER_PORT:-$CANARY_PORT}"
  else
    printf '    ports: !override []\n'
  fi
  if [ -n "${CANARY_NETWORK:-}" ]; then
    printf '    networks: !override\n'
    printf '      - %s\n' "$CANARY_NETWORK"
  fi
  if [ -n "${CANARY_BROWSER_SERVICE:-}" ]; then
    printf '  %s:\n' "$CANARY_BROWSER_SERVICE"
    printf '    container_name: %s\n' "${CANARY_BROWSER_CONTAINER:?manifest 缺 CANARY_BROWSER_CONTAINER}"
    if [ -n "${CANARY_BROWSER_PORT:-}" ]; then
      printf '    ports: !override\n'
      printf '      - "127.0.0.1:%s:%s"\n' "$CANARY_BROWSER_PORT" "${CANARY_BROWSER_CONTAINER_PORT:-9222}"
    fi
  fi
  if [ -n "${CANARY_NETWORK:-}" ]; then
    printf 'networks: !override\n'
    printf '  %s: {}\n' "$CANARY_NETWORK"
  fi
} > "$OVERRIDE_FILE"

docker compose -p "$CANARY_PROJECT" -f compose.yml -f "$OVERRIDE_FILE" up -d "${SERVICES[@]}"
echo "canary started (project=$CANARY_PROJECT services=$CANARY_SERVICES)"
