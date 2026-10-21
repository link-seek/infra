#!/usr/bin/env bash
# digest 门禁：digest-or-tag 进门即冻结为 digest（fail-closed）。
# 用法：DIGEST="$(STACK_DIR=... bash scripts/freeze-digest.sh <digest_or_tag>)"
# SWR 私有读凭证经环境变量 SWR_USER/SWR_PASS 可选传入；没有就匿名试， penetrating 都失败则 exit 1。
set -euo pipefail
STACK_DIR="${STACK_DIR:?STACK_DIR 缺失}"
WANT="${1:?digest_or_tag 缺失}"
source "$STACK_DIR/deploy.manifest"
[ -n "${PIN_REPOS:-}" ] || { echo "manifest 缺 PIN_REPOS" >&2; exit 1; }
REPO="${PIN_REPOS%% *}"
if [[ "$WANT" == sha256:* ]]; then
  echo "$WANT"
  exit 0
fi
echo "resolving tag $WANT on $REPO" >&2
if [ -n "${SWR_USER:-}" ]; then
  echo "${SWR_PASS:-}" | docker login swr.cn-north-9.myhuaweicloud.com -u "$SWR_USER" --password-stdin >/dev/null 2>&1 || true
fi
DIGEST="$(docker buildx imagetools inspect "$REPO:$WANT" --format '{{json .Manifest}}' 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('digest',''))" || true)"
[ -n "$DIGEST" ] || { echo "FAIL: tag $WANT 在 $REPO 不存在（匿名+凭证都试过）" >&2; exit 1; }
echo "frozen digest: $DIGEST" >&2
echo "$DIGEST"
