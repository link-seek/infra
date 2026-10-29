#!/usr/bin/env bash
# deliver-remote-core.sh — 快递厚脚本（deliver-stack.yml 与 img-preflight.yml 共用，唯一真相）。
# canary 三件套在 scripts/canary-{run,probe,drop}.sh（唯一真相），栈侧只留 deploy.manifest 参数表。
# 输入全走环境变量；MODE=up 走完切流，MODE=preflight 只到探针（img 场景，完事调用方自行丢 canary 或随 runner 消失）。
# 必需：STACK_DIR TARGET_IP ACTION_MODE(up/down/preflight)
#       SSH_TRANSPORT=key（默认）→ 还需 SSH_KEY_FILE/SSH_PORT；=tailscale → 走 TS SSH，不用钥匙
# 可选：CANDIDATE_DIGEST（digest 门禁已在外层冻好；为空则只读 compose 现有 pin，不改）
#       REMOTE_DIR 缺省 /root/<stack>；ENV_* 由调用方 export 进来；OPENCODE_API_KEY 供探针。
#       TS_API_KEY：栈点名 TS_JOIN_KEY 时，现场 mint reusable+ephemeral+90d 的 tag:opencode key。
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

for v in ENV_GH_TOKEN ENV_LITELLM_API_KEY ENV_OPENCODE_SERVER_PASSWORD ENV_CLOUDFLARE_API_TOKEN ENV_CF_AI_TOKEN ENV_HCLOUD_AK ENV_HCLOUD_SK ENV_SMTP_PASS; do
  export "$v"="${!v:-}"
  # render-dotenv.sh 只认 S_<SUFFIX>；调用方负责桥接（脚本头注释约定的调用方义务）
  export "S_$v"="${!v:-}"
done
# CF deploy 现签：栈点名要 CLOUDFLARE_API_TOKEN（env-sources）但没给静态值、却给了
# CF_PARENT_TOKEN → 现签 90 天子 key（读：DNS/Zone；写：Zone/DNS/Workers/Pages，供容器 wrangler 自助）。
# 不存 secret、不续期，发版即续。栈要点名却两样都没有 → 大声死（fail-closed）。网关栈无此点名，不受影响。
if grep -q "CLOUDFLARE_API_TOKEN" "$STACK_DIR/$ENV_CONF" 2>/dev/null && [ -z "${ENV_CLOUDFLARE_API_TOKEN:-}" ]; then
  set +x # 敏感段：关 trace，值只走 mask 通道
  : "${CF_PARENT_TOKEN:?FAIL: 栈要点 CLOUDFLARE_API_TOKEN 但没给值也没给 CF_PARENT_TOKEN（现签不了）}"
  echo "CF deploy 签发（90 天读写，audit 见 Cloudflare 侧 cf-deploy- 前缀 token）"
  MINTED="$(CF_PARENT_TOKEN_SANITIZED="$(printf '%s' "$CF_PARENT_TOKEN" | tr -d '\r\n ')" CF_ACCOUNT_ID="${CF_ACCOUNT_ID:-47ce24ced58f17c9fb15351adcbe67d4}" python3 - <<'PY'
import json
import os
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
BASE = "https://api.cloudflare.com/client/v4"
TOKEN = os.environ["CF_PARENT_TOKEN_SANITIZED"]
ACCOUNT_ID = os.environ["CF_ACCOUNT_ID"]
print("::add-mask::%s" % TOKEN)
def call(method, path, body=None):
    headers = {"Authorization": "Bearer " + TOKEN}
    data = None
    if body is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(body).encode()
    req = urllib.request.Request(BASE + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status, json.loads(resp.read() or b"{}")
    except urllib.error.HTTPError as exc:
        try:
            return exc.code, json.loads(exc.read() or b"{}")
        except Exception:
            return exc.code, {}
st, r = call("GET", "/accounts/%s/tokens/permission_groups?per_page=50" % ACCOUNT_ID)
groups = r.get("result") if isinstance(r.get("result"), list) else []
by_name = {str(g.get("name", "")).lower(): str(g.get("id") or "") for g in groups}
dns_id = by_name.get("dns read", "c8fed203ed3043cba015a93ad1616f1f")
zone_id = by_name.get("zone read", "82e64a83756745bbbb1c9c2701bf816b")
# 写权限（容器 wrangler/DNS/Workers 自助，owner 已批）：别名全试，缺一即 fail-closed。
# 注意：Cloudflare 组名以列表返回为准，下面的候选只是常见写法。
WRITE_ALIASES = {
    "zone edit": ["zone edit", "zone write"],
    "dns edit": ["dns edit", "dns write"],
    "workers edit": ["workers scripts edit", "workers scripts write", "workers edit", "workers write"],
    "pages edit": ["pages edit", "pages write"],
}
write_ids = []
for want, aliases in WRITE_ALIASES.items():
    got = ""
    for a in aliases:
        if by_name.get(a):
            got = by_name[a]
            break
    if not got:
        print("FAIL: 写权限组缺失（要 %s，试过 %s）；现有组名前 10：%s" % (
            want, aliases, sorted(by_name.keys())[:10]), file=sys.stderr)
        raise SystemExit(1)
    write_ids.append(got)
expires = (datetime.now(timezone.utc) + timedelta(days=90)).strftime("%Y-%m-%dT%H:%M:%SZ")
st, r = call("POST", "/accounts/%s/tokens" % ACCOUNT_ID, {
    "name": "cf-deploy-%s" % datetime.now(timezone.utc).strftime("%Y%m%d"),
    "policies": [{"effect": "allow",
                  "resources": {("com.cloudflare.api.account.%s" % ACCOUNT_ID): {"com.cloudflare.api.account.zone.*": "*"}},
                  "permission_groups": [{"id": dns_id}, {"id": zone_id}] + [{"id": i} for i in write_ids]}],
    "expires_on": expires,
})
if not r.get("success"):
    print("FAIL: CF 现签 status=%s" % st, file=sys.stderr)
    raise SystemExit(1)
value = str((r.get("result") or {}).get("value") or "")
if not value:
    print("FAIL: CF 现签无值", file=sys.stderr)
    raise SystemExit(1)
print("::add-mask::%s" % value)
print("CF_MINTED_VALUE=%s" % value)
PY
)"
  CHILD="$(printf '%s' "$MINTED" | grep '^CF_MINTED_VALUE=' | cut -d= -f2-)"
  [ -n "$CHILD" ] || { echo "FAIL: CF 现签没拿到值"; exit 1; }
  echo "::add-mask::$CHILD"
  export ENV_CLOUDFLARE_API_TOKEN="$CHILD"
  export S_ENV_CLOUDFLARE_API_TOKEN="$CHILD"
  echo "CF 现签 OK（90 天，值已进 render）"
  set -x # 敏感段结束
fi
# Workers AI deploy 现签：栈点名要 CF_AI_TOKEN（记忆 embedding 直连）但没给静态值、却给了
# CF_PARENT_TOKEN → 现签 90 天 Workers AI Read+Write 子 key。不存 secret、不续期，发版即续。
# 同 CLOUDFLARE 段：网关栈无此点名，不受影响。
if grep -q "CF_AI_TOKEN" "$STACK_DIR/$ENV_CONF" 2>/dev/null && [ -z "${ENV_CF_AI_TOKEN:-}" ]; then
  set +x # 敏感段：关 trace，值只走 mask 通道
  : "${CF_PARENT_TOKEN:?FAIL: 栈要点 CF_AI_TOKEN 但没给值也没给 CF_PARENT_TOKEN（现签不了）}"
  echo "Workers AI deploy 签发（90 天读写，audit 见 Cloudflare 侧 cf-ai-deploy- 前缀 token）"
  MINTED_AI="$(CF_PARENT_TOKEN_SANITIZED="$(printf '%s' "$CF_PARENT_TOKEN" | tr -d '\r\n ')" CF_ACCOUNT_ID="${CF_ACCOUNT_ID:-47ce24ced58f17c9fb15351adcbe67d4}" python3 - <<'PY'
import json
import os
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
BASE = "https://api.cloudflare.com/client/v4"
TOKEN = os.environ["CF_PARENT_TOKEN_SANITIZED"]
ACCOUNT_ID = os.environ["CF_ACCOUNT_ID"]
print("::add-mask::%s" % TOKEN)
def call(method, path, body=None):
    headers = {"Authorization": "Bearer " + TOKEN}
    data = None
    if body is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(body).encode()
    req = urllib.request.Request(BASE + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status, json.loads(resp.read() or b"{}")
    except urllib.error.HTTPError as exc:
        try:
            return exc.code, json.loads(exc.read() or b"{}")
        except Exception:
            return exc.code, {}
st, r = call("GET", "/accounts/%s/tokens/permission_groups?per_page=100" % ACCOUNT_ID)
groups = r.get("result") if isinstance(r.get("result"), list) else []
by_name = {str(g.get("name", "")).lower(): str(g.get("id") or "") for g in groups}
read_id = by_name.get("workers ai read", "")
write_id = by_name.get("workers ai write", "")
if not read_id or not write_id:
    print("FAIL: Workers AI Read/Write group 不在 permission_groups 里", file=sys.stderr)
    raise SystemExit(1)
expires = (datetime.now(timezone.utc) + timedelta(days=90)).strftime("%Y-%m-%dT%H:%M:%SZ")
st, r = call("POST", "/accounts/%s/tokens" % ACCOUNT_ID, {
    "name": "cf-ai-deploy-%s" % datetime.now(timezone.utc).strftime("%Y%m%d"),
    "policies": [{"effect": "allow",
                  "resources": {("com.cloudflare.api.account.%s" % ACCOUNT_ID): "*"},
                  "permission_groups": [{"id": read_id}, {"id": write_id}]}],
    "expires_on": expires,
})
if not r.get("success"):
    print("FAIL: Workers AI 现签 status=%s" % st, file=sys.stderr)
    raise SystemExit(1)
value = str((r.get("result") or {}).get("value") or "")
if not value:
    print("FAIL: Workers AI 现签无值", file=sys.stderr)
    raise SystemExit(1)
print("::add-mask::%s" % value)
print("CF_MINTED_VALUE=%s" % value)
PY
)"
  CHILD_AI="$(printf '%s' "$MINTED_AI" | grep '^CF_MINTED_VALUE=' | cut -d= -f2-)"
  [ -n "$CHILD_AI" ] || { echo "FAIL: Workers AI 现签没拿到值"; exit 1; }
  echo "::add-mask::$CHILD_AI"
  export ENV_CF_AI_TOKEN="$CHILD_AI"
  export S_ENV_CF_AI_TOKEN="$CHILD_AI"
  echo "Workers AI 现签 OK（90 天，值已进 render）"
  set -x # 敏感段结束
fi
# TS join key 现签：栈点名 TS_JOIN_KEY → 每次 deploy mint 一把 reusable+ephemeral+90d、
# 带 tag:opencode 的 auth key，render 进 .env 供容器 userspace tailscaled 启动时 join。
# 旧静态 SSH 私钥（ENV_SSH_PRIVATE_KEY_B64）已退役，本线不再触碰任何 SSH 私钥。
if grep -q '^TS_JOIN_KEY=' "$STACK_DIR/$ENV_CONF" 2>/dev/null; then
  set +x # 敏感段：关 trace，key 只走 mask 通道
  : "${TS_API_KEY:?FAIL: 栈要点 TS_JOIN_KEY 但没给 TS_API_KEY（现签不了）}"
  TSKEY="$(printf '%s' "$TS_API_KEY" | tr -d '\r\n ')"
  MINT_BODY='{"capabilities":{"devices":{"create":{"reusable":true,"ephemeral":true,"preauthorized":true,"tags":["tag:opencode"]}}},"expirySeconds":7776000}'
  MINT_RESP="$(mktemp)"
  MINT_CODE="$(curl -sS -m 30 -o "$MINT_RESP" -w '%{http_code}' -X POST -H "Authorization: Bearer $TSKEY" -H 'Content-Type: application/json' \
    -d "$MINT_BODY" \
    https://api.tailscale.com/api/v2/tailnet/-/keys 2>/tmp/ts-mint.err || true)"
  JOIN_KEY="$(python3 -c "import json; print(json.load(open('$MINT_RESP')).get('key',''))" 2>/dev/null || true)"
  if [ -z "$JOIN_KEY" ]; then
    MINT_CODE="$(curl -sS -m 30 -o "$MINT_RESP" -w '%{http_code}' -X POST -u "$TSKEY:" -H 'Content-Type: application/json' \
      -d "$MINT_BODY" \
      https://api.tailscale.com/api/v2/tailnet/-/keys 2>/tmp/ts-mint.err || true)"
    JOIN_KEY="$(python3 -c "import json; print(json.load(open('$MINT_RESP')).get('key',''))" 2>/dev/null || true)"
  fi
  if [ -z "$JOIN_KEY" ]; then
    echo "FAIL: TS join key 现签失败（HTTP $MINT_CODE）: $(head -c 400 "$MINT_RESP")" >&2
    rm -f "$MINT_RESP"
    exit 1
  fi
  rm -f "$MINT_RESP"
  echo "::add-mask::$JOIN_KEY"
  export S_ENV_TS_JOIN_KEY="$JOIN_KEY"
  echo "TS join key minted（reusable+ephemeral+90d, tag:opencode, HTTP $MINT_CODE）"
  set -x # 敏感段结束
fi
# trial（preflight）分支：LITELLM_BASE_URL 改道生产网关 tailnet 地址（生产 up 不动）。
if [ "${ACTION_MODE:-}" = "preflight" ] && grep -q '^LITELLM_BASE_URL=' "$STACK_DIR/$ENV_CONF" 2>/dev/null; then
  export S_LITELLM_BASE_URL="http://100.91.222.51:4000"
  echo "trial override: LITELLM_BASE_URL -> $S_LITELLM_BASE_URL"
fi
bash scripts/render-dotenv.sh --map "$STACK_DIR/$ENV_CONF" --example "$STACK_DIR/.env.example" --out /tmp/ci-dotenv
$SSH "mkdir -p $REMOTE_DIR" # 干净机（如 img 预检）上目录尚不存在，先建
put /tmp/ci-dotenv "$REMOTE_DIR/.env"
rm -f /tmp/ci-dotenv
cp /tmp/compose.deploy.yml /tmp/sync-compose.yml
( cd "$STACK_DIR" && tar -czf /tmp/sync-files.tgz $SYNC_FILES )
$SSH "mkdir -p $REMOTE_DIR && tar -xzf - -C $REMOTE_DIR && chmod 600 $REMOTE_DIR/.env && echo synced" < /tmp/sync-files.tgz
put /tmp/sync-compose.yml "$REMOTE_DIR/compose.yml"
# 三件套共用脚本从 scripts/ 走 stdin，同时留 /tmp 同名副本供排障/跨仓复用；
# 靶机只留本栈参数表（deploy.manifest）。
put scripts/canary-run.sh /tmp/canary-run.sh
put scripts/canary-probe.sh /tmp/canary-probe.sh
put scripts/canary-drop.sh /tmp/canary-drop.sh
put "$STACK_DIR/deploy.manifest" "$REMOTE_DIR/deploy.manifest"

# goss 二进制：CI 侧下载后与 canary 脚本同一条 tar 路上靶机（不烘镜像，版本由 manifest 钉死）。
GOSS_REMOTE=""
if [ -n "${GOSS_VERSION:-}" ]; then
  TARGET_ARCH="$($SSH 'uname -m')"
  case "$TARGET_ARCH" in
    x86_64|amd64) GOSS_ARCH=x86_64 ;;
    aarch64|arm64) GOSS_ARCH=arm64 ;;
    *) echo "FAIL: goss 不支持目标架构 $TARGET_ARCH" >&2; exit 1 ;;
  esac
  GOSS_LOCAL="/tmp/goss-${GOSS_VERSION}-linux-${GOSS_ARCH}"
  GOSS_TGZ="${GOSS_LOCAL}.tar.gz"
  if [ ! -x "$GOSS_LOCAL" ]; then
    curl -fsSL -m 120 -o "$GOSS_TGZ" \
      "https://github.com/goss-org/goss/releases/download/${GOSS_VERSION}/goss_${GOSS_VERSION#v}_linux_${GOSS_ARCH}.tar.gz"
    mkdir -p "$GOSS_LOCAL.dir"
    tar -xzf "$GOSS_TGZ" -C "$GOSS_LOCAL.dir" goss
    install -m 0755 "$GOSS_LOCAL.dir/goss" "$GOSS_LOCAL"
  fi
  GOSS_REMOTE="$REMOTE_DIR/.probe/goss"
  $SSH "mkdir -p $REMOTE_DIR/.probe"
  put "$GOSS_LOCAL" "$GOSS_REMOTE"
  $SSH "chmod 0755 '$GOSS_REMOTE'"
  echo "goss synced: $GOSS_REMOTE ($($SSH "$GOSS_REMOTE --version" 2>/dev/null || echo 'version check skipped'))"
fi

DIGEST_FOR_CANARY="${CANDIDATE_DIGEST:-$(grep -oP '(?<=@)sha256:[0-9a-f]+' /tmp/compose.deploy.yml | head -n1)}"
export REMOTE_DIR CANDIDATE_DIGEST="$DIGEST_FOR_CANARY"
export CANARY_PORT CANARY_BROWSER_PORT 2>/dev/null || true
# 探针级别：preflight 与 up 一样全跑 full（trial 经网关 override 也能真问答；贵几分钟，值）。
# UP_PROBE_LEVEL 保留兼容（未设置时默认 full）。
if [ "$ACTION_MODE" = "preflight" ]; then PROBE_LEVEL=full; else PROBE_LEVEL="${UP_PROBE_LEVEL:-full}"; fi
export PROBE_LEVEL
$SSH "REMOTE_DIR='$REMOTE_DIR' CANDIDATE_DIGEST='$DIGEST_FOR_CANARY' CANARY_PORT='${CANARY_PORT:-}' CANARY_BROWSER_PORT='${CANARY_BROWSER_PORT:-}' SWR_USER='${SWR_USER:-}' SWR_PASS='${SWR_PASS:-}' bash -s" < scripts/canary-run.sh
if $SSH "REMOTE_DIR='$REMOTE_DIR' CANDIDATE_DIGEST='$DIGEST_FOR_CANARY' CANARY_PORT='${CANARY_PORT:-}' CANARY_BROWSER_PORT='${CANARY_BROWSER_PORT:-}' PROBE_LEVEL='$PROBE_LEVEL' OPENCODE_API_KEY='${OPENCODE_API_KEY:-}' GOSS_BIN='$GOSS_REMOTE' CANARY_CONTAINER='${CANARY_CONTAINER:-}' GOSS_FILE='${GOSS_FILE:-}' MIN_GOSS_CASES='${MIN_GOSS_CASES:-}' bash -s" < scripts/canary-probe.sh; then
  echo "探针通过"
  if [ "$ACTION_MODE" = "preflight" ]; then
    echo "PREFLIGHT-OK（canary 留给调用方处置）"
  else
    echo "切流（与 canary 同镜像同 env，复用同一把随机 master）"
    # shellcheck disable=SC2086
    $SSH "cd $REMOTE_DIR && export LITELLM_MASTER_KEY=\"\$(cat .canary_master 2>/dev/null || true)\" && docker compose up -d --force-recreate $CUTOVER_SERVICES && echo CUTOVER-OK"
    $SSH "REMOTE_DIR='$REMOTE_DIR' CANARY_PORT='${CANARY_PORT:-}' CANARY_BROWSER_PORT='${CANARY_BROWSER_PORT:-}' bash -s" < scripts/canary-drop.sh >/dev/null 2>&1 || true
  fi
else
  echo "探针失败，丢弃 canary，旧容器不动"
  $SSH "REMOTE_DIR='$REMOTE_DIR' CANARY_PORT='${CANARY_PORT:-}' CANARY_BROWSER_PORT='${CANARY_BROWSER_PORT:-}' bash -s" < scripts/canary-drop.sh || true
  exit 1
fi
