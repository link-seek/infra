#!/bin/sh
# k3s-e2e-recall：在 HW41 上跑（root），经 .69 kubectl exec 进 k3s pod 做记忆召回 E2E。
# 复刻 stacks/opencode/probes/50-memory-recall.sh 的门（A 写 marker → B 新会话问 → grep 回显）。
# 用法：k3s-e2e-recall.sh <MARKER>（MARKER 由 workflow 传 run 号尾巴）。
# 注意：会在 .69 卷里留下 2~3 条 ses_k3s* 测试会话（canary 同款惯例，批量清，不逐条删）。
set -eu
MARKER="${1:?MARKER required}"
SID="ses_k3s$(printf '%s' "$MARKER" | tr -cd '0-9A-Za-z' | tail -c 9)"
K69="ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@192.168.1.69"
KX="$K69 kubectl -n opencode exec deploy/opencode -c opencode --"

echo "=== session A（写 marker=$MARKER） ==="
if timeout 100 $KX opencode run "记住：我养了一只猫叫$MARKER" 2>&1 | tail -n 15; then
  echo "OK: session A 结束"
else
  echo "E2E-A-FAIL"
  exit 1
fi
sleep 8
B_OK=0
for attempt in 1 2; do
  echo "=== session B（新会话 ${SID}${attempt}，第 $attempt 次） ==="
  if OUT="$(timeout 100 $KX opencode run --session "${SID}${attempt}" "我养的猫叫什么名字？" 2>&1)"; then
    echo "$OUT" | tail -n 15
    if printf '%s' "$OUT" | grep -Fq "$MARKER"; then
      echo "OK: 新会话召回 $MARKER"
      B_OK=1
      break
    fi
    echo "NOTE: 未回显（attempt $attempt）"
  else
    echo "NOTE: B 退出非零（attempt $attempt）"
  fi
  [ "$attempt" -lt 2 ] && sleep 8
done
[ "$B_OK" = "1" ] || { echo "E2E-B-FAIL: 新会话未召回"; exit 1; }
echo E2E-OK
