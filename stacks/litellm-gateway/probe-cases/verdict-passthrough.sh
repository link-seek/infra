#!/bin/bash
# probe-cases/verdict-passthrough.sh — 真/假 key 上游 verdict 透传。
# runner 契约：CANARY_IP、OPENCODE_API_KEY、PROBE_LEVEL；boot 轻链路跳过，full 才跑。
# 要解析 JSON 回包/多步判定，故留 sh 用例，不进 goss。
set -uo pipefail

if [ "${PROBE_LEVEL:-full}" != "full" ]; then
  echo "SKIP verdict-passthrough: PROBE_LEVEL=${PROBE_LEVEL:-}（full 才跑）"
  exit 0
fi
: "${CANARY_IP:?CANARY_IP required}"
: "${OPENCODE_API_KEY:?OPENCODE_API_KEY required for full verdict probe}"

BASE_URL="http://$CANARY_IP:4000"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
PASS=1
fail() { echo "FAIL: $1"; PASS=0; }

probe_chat() { # $1=key $2=outfile -> http code
  curl -s -m 30 -o "$2" -w '%{http_code}' \
    -H "Authorization: Bearer $1" -H 'Content-Type: application/json' \
    -d '{"model":"muse-spark-1.3-contributor","messages":[{"role":"user","content":"hi"}],"max_tokens":32}' \
    "$BASE_URL/v1/chat/completions" || echo 000
}

REAL_OUT="$TMP_DIR/real.json"
CC="$(probe_chat "$OPENCODE_API_KEY" "$REAL_OUT")"
echo "verify: real-key=$CC $(head -c 120 "$REAL_OUT")"
if grep -qi "no.connected.db\|no_db_connection" "$REAL_OUT" 2>/dev/null; then
  fail "real key 透出 No connected db"
elif [ "$CC" = "200" ]; then
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); m=d["choices"][0].get("message") or {}; assert isinstance(m.get("content"), str) or isinstance(m.get("reasoning_content"), str), "no text content keys=%s" % sorted(m.keys())' "$REAL_OUT" \
    || { fail "回包格式错"; echo "--- DEBUG full choices[0] (model chatter, no secrets) ---"; head -c 1500 "$REAL_OUT"; echo; }
elif [ "$CC" = "400" ] && grep -qi "does not support this protocol" "$REAL_OUT"; then
  : # 上游形：模型只支持 responses API
elif { [ "$CC" = "401" ] || [ "$CC" = "403" ]; } && grep -qi "upstream request failed" "$REAL_OUT"; then
  : # 上游形：key 被上游拒
else
  fail "意外状态码 $CC"
fi

FAKE_OUT="$TMP_DIR/fake.json"
IC="$(probe_chat "sk-invalid-test" "$FAKE_OUT")"
echo "verify: fake-key=$IC $(head -c 120 "$FAKE_OUT")"
if grep -qi "no.connected.db\|no_db_connection" "$FAKE_OUT" 2>/dev/null; then
  fail "fake key 透出 No connected db"
elif { [ "$IC" = "401" ] || [ "$IC" = "403" ]; } && grep -qi "upstream request failed" "$FAKE_OUT"; then
  : # OK：杂 key 透回上游 verdict
else
  fail "fake key 未透传上游"
fi

if [ "$PASS" = "1" ]; then
  echo "verdict-passthrough OK"
  exit 0
fi
exit 1
