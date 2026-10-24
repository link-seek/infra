#!/bin/bash
# canary-run.sh — 在目标机上起 canary（同镜像同 env 同网络，不映射宿主端口）。
# 输入 env：REMOTE_DIR（栈目录，compose+.env 已同步）、CANDIDATE_DIGEST（冻结 digest）。
# 约定：生成随机 master，存 $REMOTE_DIR/.canary_master（600），切流时复用同一把。
set -euo pipefail
cd "$REMOTE_DIR"
docker rm -f litellm-guard-canary 2>/dev/null || true
# 干净机（如 img 预检 runner）上 compose 栈从未 up 过，该网络不存在 → 建一个（已存在则忽略）。
# 注意：必须带上 compose 的标签，否则后续 `docker compose up` 会因 label 不符拒绝使用已存在的同名网络
# （preflight 时代从没走到 up，这 bug 一直没爆；全量试送第一次跑就抓住了）。
if ! docker network inspect litellm-guard_default >/dev/null 2>&1; then
  docker network create \
    --label com.docker.compose.network=gw-net \
    --label com.docker.compose.project=litellm-gateway \
    litellm-guard_default
fi
# 干净机适配：compose 绑了生产机才有的 172.19.0.1（172.17.0.1 是 docker0 自带）。
# 靶机上没有就给 lo 补一个 /32（生产机自带，走 grep 直接跳过；只影响本机绑端口，不碰容器网段）。
# 不改 compose 文件本身：测的就是要发的那份（试送保真）。
ip addr show | grep -qw 172.19.0.1 || ip addr add 172.19.0.1/32 dev lo
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
docker run -d --name litellm-guard-canary \
  --init \
  --env-file .env \
  -e LITELLM_MASTER_KEY="$LITELLM_MASTER_KEY" \
  -e DISABLE_ADMIN_UI=True \
  -e RULES_FILE=/app/guard-rules.json \
  --network litellm-guard_default \
  "$NEW_IMG" \
  --config /app/config.yaml --port 4000 --host 0.0.0.0
echo "canary started"
