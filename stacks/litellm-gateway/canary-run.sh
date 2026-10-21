#!/bin/bash
# canary-run.sh — 在目标机上起 canary（同镜像同 env 同网络，不映射宿主端口）。
# 输入 env：REMOTE_DIR（栈目录，compose+.env 已同步）、CANDIDATE_DIGEST（冻结 digest）。
# 约定：生成随机 master，存 $REMOTE_DIR/.canary_master（600），切流时复用同一把。
set -euo pipefail
cd "$REMOTE_DIR"
docker rm -f litellm-guard-canary 2>/dev/null || true
NEW_IMG="$(grep 'image:' compose.yml | head -1 | sed 's/.*image: *//')"
echo "canary image: $NEW_IMG (want $CANDIDATE_DIGEST)"
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
