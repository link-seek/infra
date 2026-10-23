#!/bin/bash
# canary-probe.sh — 探 canary（网关栈）：就绪 + 真 key + 假 key + 黑名单。任一红即非零退出。
# 输入 env：REMOTE_DIR、OPENCODE_API_KEY（真 key，现取 secret）、PROBE_LEVEL（boot=就绪+黑名单轻链路/full=再加真假 key 上游 verdict，默认 full）。
set -euo pipefail
PROBE_LEVEL="${PROBE_LEVEL:-full}"
CANARY_IP=$(docker inspect litellm-guard-canary --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
echo "canary ip: $CANARY_IP (level=$PROBE_LEVEL)"
PASS=1

READY=""
for i in $(seq 1 18); do
  sleep 10
  C0="$(curl -s -m 8 -o /dev/null -w '%{http_code}' http://$CANARY_IP:4000/v1/models || echo 000)"
  echo "ready-probe#$i -> $C0"
  if [ "$C0" = "200" ]; then READY=1; break; fi
done
if [ -z "$READY" ]; then
  echo "FAIL: canary 3 分钟未就绪"
  docker logs litellm-guard-canary --tail 60 || true
  docker rm -f litellm-guard-canary
  exit 1
fi

probe_chat() { # $1=key $2=outfile -> http code
  curl -s -m 30 -o "$2" -w '%{http_code}' \
    -H "Authorization: Bearer $1" -H 'Content-Type: application/json' \
    -d '{"model":"muse-spark-1.3-contributor","messages":[{"role":"user","content":"hi"}],"max_tokens":1}' \
    http://$CANARY_IP:4000/v1/chat/completions || echo 000
}

if [ "$PROBE_LEVEL" = "full" ]; then
CC="$(probe_chat "$OPENCODE_API_KEY" /tmp/cc.json)"
echo "verify: real-key=$CC $(head -c 120 /tmp/cc.json)"
if grep -qi "no.connected.db\|no_db_connection" /tmp/cc.json 2>/dev/null; then
  echo "FAIL: real key 透出 No connected db"; PASS=0
elif [ "$CC" = "200" ]; then
  python3 -c "import json;d=json.load(open('/tmp/cc.json'));assert isinstance(d['choices'][0]['message']['content'],str)" || { echo "FAIL: 回包格式错"; PASS=0; }
elif [ "$CC" = "400" ] && grep -qi "does not support this protocol" /tmp/cc.json; then
  : # 上游形：模型只支持 responses API
elif { [ "$CC" = "401" ] || [ "$CC" = "403" ]; } && grep -qi "upstream request failed" /tmp/cc.json; then
  : # 上游形：key 被上游拒
else
  echo "FAIL: 意外状态码 $CC"; PASS=0
fi

IC="$(probe_chat "sk-invalid-test" /tmp/ic.json)"
echo "verify: fake-key=$IC $(head -c 120 /tmp/ic.json)"
if grep -qi "no.connected.db\|no_db_connection" /tmp/ic.json 2>/dev/null; then
  echo "FAIL: fake key 透出 No connected db"; PASS=0
elif { [ "$IC" = "401" ] || [ "$IC" = "403" ]; } && grep -qi "upstream request failed" /tmp/ic.json; then
  : # OK：杂 key 透回上游 verdict
else
  echo "FAIL: fake key 未透传上游"; PASS=0
fi
fi # PROBE_LEVEL=full（真假 key 上游 verdict 只在细测跑；生产轻链路只验就绪+黑名单）

# 黑名单（以 canary 内实际生效的名单为准，从运行中的容器现场取，不读仓库拷贝）
docker cp litellm-guard-canary:/app/models-denied.json /tmp/probe-denied.json
DENIED="$(python3 -c "import json;d=json.load(open('/tmp/probe-denied.json'));print(d[0] if d else '')")"
if [ -z "$DENIED" ]; then
  echo "verify: denied 名单为空 = 全放行（按文档语义跳过黑名单断言）"
else
BL="$(curl -s -m 30 -o /tmp/bl.json -w '%{http_code}' \
  -H "Authorization: Bearer $OPENCODE_API_KEY" -H 'Content-Type: application/json' \
  -d "{\"model\":\"$DENIED\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":1}" \
  http://$CANARY_IP:4000/v1/chat/completions || echo 000)"
echo "verify: denied($DENIED)=$BL $(head -c 120 /tmp/bl.json)"
if [ "$BL" != "400" ]; then echo "FAIL: 黑名单未拦"; PASS=0; fi
fi

if [ "$PASS" = "1" ]; then echo "PROBE OK"; else docker logs litellm-guard-canary --tail 60 || true; exit 1; fi
