#!/bin/sh
# k3s-e2e-recall：在 HW41 上跑（root），经 .69 kubectl exec 进 k3s pod 做记忆召回 E2E。
# 复刻 stacks/opencode/probes/50-memory-recall.sh 的门（A 写 marker → B 新会话问 → grep 回显）。
# 用法：k3s-e2e-recall.sh <MARKER>（MARKER 由 workflow 传 run 号尾巴）。
# 注意：会在 .69 卷里留下 2~3 条 ses_k3s* 测试会话（canary 同款惯例，批量清，不逐条删）。
set -eu
MARKER="${1:?MARKER required}"
# 测试模型：默认 muse-spark（用户真实路径，经 app-connector 出）；上游抽风时可 E2E_MODEL=big-pickle 降级验证链路。
MODEL="${E2E_MODEL:-muse-spark-1.3-contributor}"
SID="ses_k3s$(printf '%s' "$MARKER" | tr -cd '0-9A-Za-z' | tail -c 9)"
K69="ssh -n -o BatchMode=yes -o StrictHostKeyChecking=no root@192.168.1.69"
KX="$K69 kubectl -n opencode exec deploy/opencode -c opencode --"

# 0. 网关预检（读 pod 内 URL；POST 无 key 打一次：200/400/401/404=网关活着，其余/超时=FAIL，两次机会）
GWURL="$($K69 "kubectl -n opencode exec deploy/opencode -c opencode -- printenv LITELLM_BASE_URL" | tr -d '[:space:]')"
[ -n "$GWURL" ] || { echo "E2E-GW-URL-FAIL"; exit 1; }
echo "gw url=$GWURL"
GWCODE=""
for i in 1 2; do
  GWCODE="$($K69 "kubectl -n opencode exec deploy/opencode -c opencode -- curl -s -m 20 -o /dev/null -w '%{http_code}' -X POST '$GWURL/v1/chat/completions' -H 'Content-Type: application/json' -d '{\"model\":\"x\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}'" || true)"
  echo "gw post try$i: $GWCODE"
  case "$GWCODE" in 200|400|401|404) break;; *) sleep 10;; esac
done
case "$GWCODE" in 200|400|401|404) echo "gw alive: $GWCODE";; *) echo "E2E-GW-FAIL http=$GWCODE"; exit 1;; esac

# 0.6 直调对照（绕开 opencode CLI：pod 直 POST 网关，key 只进内存不落地不打印）
# 用途：CLI 挂而直调通 => CLI/配置问题；直调也挂 => 网关/上游问题。
# 注意：LITELLM_API_KEY 只在 curl 参数里展开，脚本全程 set +x 关闭，日志只留状态码。
DKEY="$($K69 "kubectl -n opencode exec deploy/opencode -c opencode -- printenv LITELLM_API_KEY" | tr -d '[:space:]')"
[ -n "$DKEY" ] || { echo "E2E-KEY-FAIL"; exit 1; }
echo "::add-mask::$DKEY"
for DM in big-pickle muse-spark-1.3-contributor; do
  DCODE="$($K69 "kubectl -n opencode exec deploy/opencode -c opencode -- curl -s -m 60 -o /dev/null -w '%{http_code}' -X POST '$GWURL/v1/chat/completions' -H \"Authorization: Bearer $DKEY\" -H 'Content-Type: application/json' -d '{\"model\":\"$DM\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":5}'" || true)"
  echo "direct model=$DM http=$DCODE"
done

# 0.5 烟雾（纯模型，不碰记忆：分清模型路 vs 记忆路）
set +e
S_OUT="$(timeout 120 $KX opencode run --model "$MODEL" "1+1等于几？只答数字" 2>&1)"; S_RC=$?
set -e
echo "$S_OUT" | tail -n 10
echo "smoke rc=$S_RC"
[ "$S_RC" = 0 ] || { echo "E2E-SMOKE-FAIL rc=$S_RC"; exit 1; }
echo SMOKE-OK

echo "=== session A（写 marker=$MARKER） ==="
set +e
A_OUT="$(timeout 150 $KX opencode run --model "$MODEL" "记住：我养了一只猫叫$MARKER" 2>&1)"; A_RC=$?
set -e
echo "$A_OUT" | tail -n 25
[ "$A_RC" = 0 ] || { echo "E2E-A-FAIL rc=$A_RC"; exit 1; }
echo "OK: session A 结束"
sleep 8
B_OK=0
for attempt in 1 2; do
  echo "=== session B（新会话 ${SID}${attempt}，第 $attempt 次） ==="
  set +e
  B_OUT="$(timeout 150 $KX opencode run --model "$MODEL" --session "${SID}${attempt}" "我养的猫叫什么名字？" 2>&1)"; B_RC=$?
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
