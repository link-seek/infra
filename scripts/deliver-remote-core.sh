#!/usr/bin/env bash
# deliver-remote-core.sh — 快递厚脚本（deliver-stack.yml 与 img-preflight.yml 共用，唯一真相）。
# 输入全走环境变量；MODE=up 走完切流，MODE=preflight 只到探针（img 场景，完事调用方自行丢 canary 或随 runner 消失）。
# 必需：STACK_DIR TARGET_IP ACTION_MODE(up/down/preflight)
#       SSH_TRANSPORT=key（默认）→ 还需 SSH_KEY_FILE/SSH_PORT；=tailscale → 走 TS SSH，不用钥匙
# 可选：CANDIDATE_DIGEST（digest 门禁已在外层冻好；为空则只读 compose 现有 pin，不改）
#       REMOTE_DIR 缺省 /root/<stack>；ENV_* 由调用方 export 进来；OPENCODE_API_KEY 供探针。
set -euo pipefail
echo "CORE-START stack=${STACK_DIR:-?} target=${TARGET_IP:-?} action=${ACTION_MODE:-?} digest=${CANDIDATE_DIGEST:-none} transport=${SSH_TRANSPORT:-key}"
set -x
: "${STACK_DIR:?}" : "${TARGET_IP:?}" : "${ACTION_MODE:?}"
SSH_PORT="${SSH_PORT:-2244}"
REMOTE_DIR="${REMOTE_DIR:-/root/$STACK_DIR}"
SSH_TRANSPORT="${SSH_TRANSPORT:-key}"
if [ "$SSH_TRANSPORT" = "tailscale" ]; then
  # TS SSH 自己校验主机身份（不读 known_hosts），也不支持 scp/sftp：文件一律 tar 流
  SSH="tailscale ssh root@$TARGET_IP"
else
  : "${SSH_KEY_FILE:?key 传输需要 SSH_KEY_FILE（或改用 SSH_TRANSPORT=tailscale）}"
  SSH="ssh -o BatchMode=yes -p $SSH_PORT -i $SSH_KEY_FILE root@$TARGET_IP"
fi
put() { # put <本地文件> <远端绝对路径>
  local src="$1" dst="$2" ddir sbase base
  ddir="$(dirname "$dst")"; sbase="$(basename "$src")"; base="$(basename "$dst")"
  if [ "$SSH_TRANSPORT" = "tailscale" ]; then
    # TS SSH 不带 sftp/scp：走 tar 流；包内名单≠目标名时 mv 改名（等价 scp 语义），最后验文件存在
    tar -czf - -C "$(dirname "$src")" "$sbase" | $SSH "mkdir -p '$ddir' && tar -xzf - -C '$ddir' && { [ '$sbase' = '$base' ] || mv -f '$ddir/$sbase' '$dst'; } && test -f '$dst'"
  else
    scp -o BatchMode=yes -P "$SSH_PORT" -i "$SSH_KEY_FILE" "$src" "root@$TARGET_IP:$dst"
  fi
}
# shellcheck disable=SC1090
source "$STACK_DIR/deploy.manifest"
REMOTE_DIR="${REMOTE_DIR:-/root/$STACK_DIR}"

if [ "$ACTION_MODE" = "down" ]; then
  $SSH "cd $REMOTE_DIR && docker compose down && echo DOWN-OK"
  exit 0
fi

if [ -n "${CANDIDATE_DIGEST:-}" ]; then
  case "$CANDIDATE_DIGEST" in sha256:*) :;; *) echo "FAIL: CANDIDATE_DIGEST 必须是冻结 digest，收到 $CANDIDATE_DIGEST（tag 请先过 freeze-digest.sh）" >&2; exit 1;; esac
  cp "$STACK_DIR/compose.yml" /tmp/compose.deploy.yml
  for repo in $PIN_REPOS; do
    # shellcheck disable=SC2016
    sed -i -E "s|(${repo}@)sha256:[0-9a-f]+|\1${CANDIDATE_DIGEST}|g" /tmp/compose.deploy.yml
  done
  grep -c "$CANDIDATE_DIGEST" /tmp/compose.deploy.yml | grep -qv '^0$' || { echo "FAIL: pin 未冻住 $CANDIDATE_DIGEST"; exit 1; }
else
  cp "$STACK_DIR/compose.yml" /tmp/compose.deploy.yml
fi

for v in ENV_GH_TOKEN ENV_LITELLM_API_KEY ENV_OPENCODE_SERVER_PASSWORD ENV_CLOUDFLARE_API_TOKEN ENV_CF_AI_TOKEN ENV_HCLOUD_AK ENV_HCLOUD_SK ENV_SSH_PRIVATE_KEY_B64 ENV_SMTP_PASS; do
  export "$v"="${!v:-}"
done
bash scripts/render-dotenv.sh --map "$STACK_DIR/$ENV_CONF" --example "$STACK_DIR/.env.example" --out /tmp/ci-dotenv
$SSH "mkdir -p $REMOTE_DIR" # 干净机（如 img 预检）上目录尚不存在，先建
put /tmp/ci-dotenv "$REMOTE_DIR/.env"
rm -f /tmp/ci-dotenv
cp /tmp/compose.deploy.yml /tmp/sync-compose.yml
( cd "$STACK_DIR" && tar -czf /tmp/sync-files.tgz $SYNC_FILES )
$SSH "mkdir -p $REMOTE_DIR && tar -xzf - -C $REMOTE_DIR && chmod 600 $REMOTE_DIR/.env && echo synced" < /tmp/sync-files.tgz
put /tmp/sync-compose.yml "$REMOTE_DIR/compose.yml"
put "$STACK_DIR/canary-run.sh" /tmp/canary-run.sh
put "$STACK_DIR/canary-probe.sh" /tmp/canary-probe.sh

DIGEST_FOR_CANARY="${CANDIDATE_DIGEST:-$(grep -oP '(?<=@)sha256:[0-9a-f]+' /tmp/compose.deploy.yml | head -n1)}"
export REMOTE_DIR CANDIDATE_DIGEST="$DIGEST_FOR_CANARY"
export CANARY_PORT CANARY_BROWSER_PORT 2>/dev/null || true
# 探针级别：preflight 恒 boot（装上+启动自测）；up 看栈 manifest 的 UP_PROBE_LEVEL（网关 boot 轻链路/opencode full 含 drain 活证明）
if [ "$ACTION_MODE" = "preflight" ]; then PROBE_LEVEL=boot; else PROBE_LEVEL="${UP_PROBE_LEVEL:-boot}"; fi
export PROBE_LEVEL
$SSH "REMOTE_DIR='$REMOTE_DIR' CANDIDATE_DIGEST='$DIGEST_FOR_CANARY' CANARY_PORT='${CANARY_PORT:-}' CANARY_BROWSER_PORT='${CANARY_BROWSER_PORT:-}' SWR_USER='${SWR_USER:-}' SWR_PASS='${SWR_PASS:-}' bash -s" < "$STACK_DIR/canary-run.sh"
if $SSH "REMOTE_DIR='$REMOTE_DIR' CANDIDATE_DIGEST='$DIGEST_FOR_CANARY' CANARY_PORT='${CANARY_PORT:-}' CANARY_BROWSER_PORT='${CANARY_BROWSER_PORT:-}' PROBE_LEVEL='$PROBE_LEVEL' OPENCODE_API_KEY='${OPENCODE_API_KEY:-}' bash -s" < "$STACK_DIR/canary-probe.sh"; then
  echo "探针通过"
  if [ "$ACTION_MODE" = "preflight" ]; then
    echo "PREFLIGHT-OK（canary 留给调用方处置）"
  else
    echo "切流（与 canary 同镜像同 env，复用同一把随机 master）"
    # shellcheck disable=SC2086
    $SSH "cd $REMOTE_DIR && export LITELLM_MASTER_KEY=\"\$(cat .canary_master 2>/dev/null || true)\" && docker compose up -d --force-recreate $CUTOVER_SERVICES && echo CUTOVER-OK"
    $SSH "REMOTE_DIR='$REMOTE_DIR' CANARY_PORT='${CANARY_PORT:-}' CANARY_BROWSER_PORT='${CANARY_BROWSER_PORT:-}' bash -s" < "$STACK_DIR/canary-drop.sh" >/dev/null 2>&1 || true
  fi
else
  echo "探针失败，丢弃 canary，旧容器不动"
  $SSH "REMOTE_DIR='$REMOTE_DIR' CANARY_PORT='${CANARY_PORT:-}' CANARY_BROWSER_PORT='${CANARY_BROWSER_PORT:-}' bash -s" < "$STACK_DIR/canary-drop.sh" || true
  exit 1
fi
