#!/bin/sh
# k3s-e2e-recall：在 HW41 上跑（root），经 .69 kubectl exec 进 k3s pod 做记忆召回 E2E。
# 复刻 stacks/opencode/probes/50-memory-recall.sh 的门（A 写 marker → B 新会话问 → grep 回显）。
# 用法：k3s-e2e-recall.sh <MARKER>（MARKER 由 workflow 传 run 号尾巴）。
# 注意：会在 .69 卷里留下 2~3 条 ses_k3s* 测试会话（canary 同款惯例，批量清，不逐条删）。
set -eu
MARKER="${1:?MARKER required}"
SID="ses_k3s$(printf '%s' "$MARKER" | tr -cd '0-9A-Za-z' | tail -c 9)"
K69="ssh -n -o BatchMode=yes -o StrictHostKeyChecking=no root@192.168.1.69"
KX="$K69 kubectl -n opencode exec deploy/opencode -c opencode --"

# 0. 网关预检（读 pod 内渲染好的 URL；根路径本来就 503，打 /v1/models 判 200；fail-fast）
GWURL="$($K69 "kubectl -n opencode exec deploy/opencode -c opencode -- printenv LITELLM_BASE_URL" | tr -d '[:space:]')"
[ -n "$GWURL" ] || { echo "E2E-GW-URL-FAIL"; exit 1; }
echo "gw url=$GWURL"
GWCODE="$($K69 "kubectl -n opencode exec deploy/opencode -c opencode -- curl -s -m 15 -o /dev/null -w '%{http_code}' '$GWURL/v1/models'")"
[ "$GWCODE" = "200" ] || { echo "E2E-GW-FAIL http=$GWCODE"; exit 1; }
echo "gw models: $GWCODE"

echo "=== session A（写 marker=$MARKER） ==="
set +e
A_OUT="$(timeout 150 $KX opencode run "记住：我养了一只猫叫$MARKER" 2>&1)"; A_RC=$?
set -e
echo "$A_OUT" | tail -n 25
[ "$A_RC" = 0 ] || { echo "E2E-A-FAIL rc=$A_RC"; exit 1; }
echo "OK: session A 结束"
sleep 8
B_OK=0
for attempt in 1 2; do
  echo "=== session B（新会话 ${SID}${attempt}，第 $attempt 次） ==="
  set +e
  B_OUT="$(timeout 150 $KX opencode run --session "${SID}${attempt}" "我养的猫叫什么名字？" 2>&1)"; B_RC=$?
  set -e
  echo "$B_OUT" | tail -n 25
  echo "B rc=$B_RC"
  if [ "$B_RC" = 0 ] && printf '%s' "$B_OUT" | grep -Fq "$MARKER"; then
    echo "OK: 新会话召回 $MARKER"
    B_OK=1
    break
  fi
  echo "NOTE: 未回显或非零（attempt $attempt）"
  [ "$attempt" -lt 2 ] && sleep 8
done
[ "$B_OK" = "1" ] || { echo "E2E-B-FAIL: 新会话未召回"; exit 1; }
echo E2E-OK
