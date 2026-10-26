#!/bin/bash
# canary-run.sh — compose 起 canary（与切流同一份 compose.yml，只隔离端口与网络）。
# 输入 env：REMOTE_DIR（栈目录，compose+.env 已同步）、CANDIDATE_DIGEST（冻结 digest）。
# 约定：生成随机 master，存 $REMOTE_DIR/.canary_master（600），切流时复用同一把。
set -euo pipefail
cd "$REMOTE_DIR"
docker compose -p litellm-guard-canary down 2>/dev/null || true
NEW_IMG="$(grep -E 'image:[[:space:]]*[^[:space:]]+@sha256:[0-9a-f]+' compose.yml | head -1 | sed 's/.*image: *//')"
[ -n "$NEW_IMG" ] || { echo "FAIL: compose 里找不到 digest pin 的 image 行（schema 门应已拦下）"; exit 1; }
echo "canary image: $NEW_IMG (want $CANDIDATE_DIGEST)"
# 干净机（如 img 预检 runner）无 registry 凭证时先登录；有则复用宿主已有凭证
if [ -n "${SWR_USER:-}" ]; then
  REG="${NEW_IMG%%/*}"
  case "$REG" in *.*) printf '%s' "${SWR_PASS:-}" | docker login "$REG" -u "$SWR_USER" --password-stdin;; esac
fi
docker pull "$NEW_IMG"
export LITELLM_MASTER_KEY="sk-$(openssl rand -hex 32)"
printf '%s' "$LITELLM_MASTER_KEY" > "$REMOTE_DIR/.canary_master"
chmod 600 "$REMOTE_DIR/.canary_master"
# override 只做隔离（端口/网络），不等价替换启动定义：
# image/env/command 全走底包 compose.yml（真源唯一，不分叉）。
# ports 用 !override 而不用默认合并：底包 3 条宿主绑定漏进 canary 会在生产机撞车
# （opencode 栈 run 40257988557 实锤；门槛 Compose 2.24.4，hw-21 v2.27.1 已验）。
# networks 用 !override 切到 canary 自有网络：底包 gw-net 是具名生产网络，
# 合并进来会导致 canary 挂生产网、down 时还可能删生产网；自有网络探针照样直连容器 IP。
cat > /tmp/canary-override.yml <<'EOF'
services:
  litellm-guard:
    container_name: litellm-guard-canary
    ports: !override []
    networks: !override
      - canary-net
networks: !override
  canary-net: {}
EOF
docker compose -p litellm-guard-canary -f compose.yml -f /tmp/canary-override.yml up -d
echo "canary started"
