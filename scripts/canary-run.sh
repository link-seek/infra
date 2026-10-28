#!/bin/bash
# canary-run.sh — 共用 canary 起栈函数（各栈只读 deploy.manifest 参数，不再各写一份）。
# 输入 env：REMOTE_DIR（栈目录，compose+.env 已同步）、CANDIDATE_DIGEST（冻结 digest）。
# 栈参数（deploy.manifest）：CANARY_PROJECT / CANARY_SERVICE_SPECS / CANARY_UP_SERVICES /
#   CANARY_IMAGE_MATCH / CANARY_PORT；SERVICE_SPECS 形如
#   service|container_name|宿主端口(逗号分隔)|hostname|env(K=V;...)|network
# 约定：网关生成随机 master，存 $REMOTE_DIR/.canary_master（600），切流时复用同一把。
set -euo pipefail
: "${REMOTE_DIR:?REMOTE_DIR required}"
: "${CANARY_PROJECT:?CANARY_PROJECT required}"
: "${CANARY_SERVICE_SPECS:?CANARY_SERVICE_SPECS required}"
cd "$REMOTE_DIR"

OVERRIDE_FILE=/tmp/canary-override.yml
docker compose -p "$CANARY_PROJECT" down 2>/dev/null || true

if [ -n "${CANARY_IMAGE_MATCH:-}" ]; then
  NEW_IMG="$(grep -E 'image:[[:space:]]*[^[:space:]]+@sha256:[0-9a-f]+' compose.yml | grep -F -- "$CANARY_IMAGE_MATCH" | head -1 | sed 's/.*image: *//')"
else
  NEW_IMG="$(grep -E 'image:[[:space:]]*[^[:space:]]+@sha256:[0-9a-f]+' compose.yml | head -1 | sed 's/.*image: *//')"
fi
[ -n "$NEW_IMG" ] || { echo "FAIL: compose 里找不到 digest pin 的 image 行（schema 门应已拦下）"; exit 1; }
echo "canary image: $NEW_IMG (want $CANDIDATE_DIGEST)"

# 干净机（如 img 预检 runner）无 registry 凭证时先登录；有则复用宿主已有凭证
if [ -n "${SWR_USER:-}" ]; then
  REG="${NEW_IMG%%/*}"
  case "$REG" in *.*) printf '%s' "${SWR_PASS:-}" | docker login "$REG" -u "$SWR_USER" --password-stdin;; esac
fi
docker pull "$NEW_IMG"

# 网关的 master 只走进程环境：canary 随机生成，切流复用同一把。
if [ -n "${CANARY_MASTER_FILE:-}" ]; then
  LITELLM_MASTER_KEY="sk-$(openssl rand -hex 32)"
  export LITELLM_MASTER_KEY
  printf '%s' "$LITELLM_MASTER_KEY" > "$REMOTE_DIR/$CANARY_MASTER_FILE"
  chmod 600 "$REMOTE_DIR/$CANARY_MASTER_FILE"
fi

# override 只做隔离（端口/网络/hostname），不等价替换启动定义：
# image/env/command 全走底包 compose.yml（真源唯一，不分叉）。
# ports 用 !override 而不用默认合并：底包宿主绑定漏进 canary 会在生产机撞车
# （opencode 栈 run 40257988557 实锤；门槛 Compose 2.24.4，hw-21 v2.27.1 已验）。
# networks 用 !override 切到 canary 自有网络：底包具名生产网络合并进来会导致 canary
# 挂生产网、down 时还可能删生产网；自有网络探针照样直连容器 IP。
{
  printf 'services:\n'
} > "$OVERRIDE_FILE"
OVERRIDE_NETWORKS=""
while IFS='|' read -r svc cname ports hostname envspec network; do
  [ -n "$svc" ] || continue
  {
    printf '  %s:\n' "$svc"
    [ -n "$cname" ] && printf '    container_name: %s\n' "$cname"
    [ -n "$hostname" ] && printf '    hostname: %s\n' "$hostname"
    if [ -n "${envspec:-}" ]; then
      printf '    environment:\n'
      IFS=';' read -ra envpairs <<< "$envspec"
      for pair in "${envpairs[@]}"; do
        [ -n "$pair" ] || continue
        printf '      %s: %s\n' "${pair%%=*}" "${pair#*=}"
      done
      unset IFS
    fi
    if [ -n "${ports:-}" ]; then
      printf '    ports: !override\n'
      IFS=',' read -ra portlist <<< "$ports"
      for p in "${portlist[@]}"; do
        [ -n "$p" ] && printf '      - "%s"\n' "$p"
      done
      unset IFS
    else
      printf '    ports: !override []\n'
    fi
    if [ -n "${network:-}" ]; then
      printf '    networks: !override\n'
      IFS=',' read -ra netlist <<< "$network"
      for n in "${netlist[@]}"; do
        [ -n "$n" ] || continue
        printf '      - %s\n' "$n"
        OVERRIDE_NETWORKS="${OVERRIDE_NETWORKS}${n}"$'\n'
      done
      unset IFS
    fi
  } >> "$OVERRIDE_FILE"
done <<< "$CANARY_SERVICE_SPECS"
if [ -n "$OVERRIDE_NETWORKS" ]; then
  printf 'networks: !override\n' >> "$OVERRIDE_FILE"
  while IFS= read -r n; do
    [ -n "$n" ] && printf '  %s: {}\n' "$n" >> "$OVERRIDE_FILE"
  done <<< "$(printf '%s' "$OVERRIDE_NETWORKS" | sort -u)"
fi

# shellcheck disable=SC2086
docker compose -p "$CANARY_PROJECT" -f compose.yml -f "$OVERRIDE_FILE" up -d ${CANARY_UP_SERVICES:-}
if [ -n "${CANARY_PORT:-}" ]; then
  echo "canary started on :$CANARY_PORT"
else
  echo "canary started"
fi
