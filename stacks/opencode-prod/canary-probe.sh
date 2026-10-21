#!/bin/bash
# canary-probe.sh — 探 canary（opencode 栈）：4097 就绪 + 双镜像 ID + drain 活探针。任一红即非零退出。
# 输入 env：REMOTE_DIR、CANDIDATE_DIGEST、CANARY_PORT。
# 网关 capability-detect：canary 机上有网关才强制 drain（img 机无网关则跳过，prod 机恒在）。
set -euo pipefail
cd "$REMOTE_DIR"
CANARY_PORT="${CANARY_PORT:-14097}"
PASS=1

CODE=""
for i in $(seq 1 24); do
  sleep 5
  CODE="$(curl -s -m 5 -o /dev/null -w '%{http_code}' http://127.0.0.1:$CANARY_PORT/ || echo 000)"
  echo "ready#$i -> $CODE"
  if [ "$CODE" = "200" ]; then break; fi
done
if [ "$CODE" != "200" ]; then echo "FAIL: canary 未就绪"; PASS=0; fi

PIN_TOOLS="$(grep -oP 'image: \K\S+opencode-tools@\S+' compose.yml | head -n1)"
EXP_TOOLS="$(docker inspect "$PIN_TOOLS" --format '{{.Id}}')"
RUN_TOOLS="$(docker inspect opencode-prod-canary --format '{{.Image}}')"
echo "image-id: run=$RUN_TOOLS want=$EXP_TOOLS"
if [ "$RUN_TOOLS" != "$EXP_TOOLS" ]; then echo "FAIL: canary 镜像 ID 与 pin 不符"; PASS=0; fi

if curl -s -m 5 -o /dev/null http://127.0.0.1:4000/v1/models; then
  echo "gateway present -> drain 强制执行"
  DRAIN_OUT="$(docker exec opencode-prod-canary opencode run "reply with exactly: DRAIN-OK" 2>&1 || true)"
  echo "drain: $(echo "$DRAIN_OUT" | tail -n 3)"
  if echo "$DRAIN_OUT" | grep -q "DRAIN-OK"; then
    echo "DRAIN OK: key 透传网关生效"
  else
    echo "FAIL: drain 未回 DRAIN-OK"; PASS=0
  fi
else
  echo "SKIP drain: 本机无网关（img 预检场景），prod 机恒强制执行"
fi

if [ "$PASS" = "1" ]; then echo "PROBE OK"; else exit 1; fi
