#!/bin/bash
# canary-probe.sh — 探 canary（opencode 栈）：4097 就绪 + 双镜像 ID + 容器进 tailnet + drain 活探针。任一红即非零退出。
# 输入 env：REMOTE_DIR、CANDIDATE_DIGEST、CANARY_PORT、PROBE_LEVEL（boot=就绪+镜像 ID/full=再加 drain，默认 full）。
# 网关 capability-detect：canary 机上有网关才强制 drain（img 机无网关则跳过，prod 机恒在）。
set -euo pipefail
cd "$REMOTE_DIR"
PROBE_LEVEL="${PROBE_LEVEL:-full}"
echo "probe level: $PROBE_LEVEL"
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

# 进网自证：容器 userspace tailscaled 必须 Running，且宿主 tailnet 设备表能看到它。
# 这步同时覆盖 img-preflight（容器在靶机进网）与 prod canary；红即 fail-closed。
TS_JSON="$(docker exec opencode-prod-canary tailscale --socket=/var/run/tailscale/tailscaled.sock status --json 2>/dev/null || true)"
if [ -z "$TS_JSON" ]; then
  echo "FAIL: 容器内 tailscale status 无输出（binary 缺失 / tailscaled 未起）"; PASS=0
else
  TS_SELF="$(printf '%s' "$TS_JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); s=d.get("Self") or {}; print(json.dumps({"host":s.get("HostName"),"ip":(s.get("TailscaleIPs") or [""])[0],"state":d.get("BackendState") or ""}))')"
  echo "tailscale-self: $TS_SELF"
  TS_IP="$(printf '%s' "$TS_SELF" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("ip") or "")')"
  TS_STATE="$(printf '%s' "$TS_SELF" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("state") or "")')"
  if [ "$TS_STATE" != "Running" ] || [ -z "$TS_IP" ]; then
    echo "FAIL: 容器未进 tailnet（state=$TS_STATE ip=$TS_IP）"; PASS=0
  else
    PEER=""
    # 新节点进 netmap 要等（eventual consistency；keyscan 12×15s 教训，30s 太急）。
    for i in $(seq 1 12); do
      PEER="$(tailscale status --json 2>/dev/null | TS_IP="$TS_IP" python3 -c 'import json,os,sys; ip=os.environ["TS_IP"]; d=json.load(sys.stdin); print(next((p.get("HostName","") for p in d.get("Peer",{}).values() if ip in (p.get("TailscaleIPs") or [])), ""))' || true)"
      [ -n "$PEER" ] && break
      sleep 15
    done
    if [ -z "$PEER" ]; then
      echo "FAIL: 宿主 tailnet 设备表看不到容器 $TS_IP（12 次/约 3min）"; PASS=0
    else
      echo "tailnet peer: $PEER ($TS_IP)"
    fi
  fi
fi

if [ "$PROBE_LEVEL" = "full" ]; then
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
else
  echo "SKIP drain: boot 轻链路不跑 drain（细测才跑）"
fi

if [ "$PASS" = "1" ]; then echo "PROBE OK"; else exit 1; fi
