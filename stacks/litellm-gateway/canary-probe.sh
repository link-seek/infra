#!/bin/bash
# canary-probe.sh — 网关 goss runner：拉齐二进制/用例，跑 goss（junit 落盘）+ probe-cases，统一表与底线断言。任一红即非零退出。
# 输入 env：REMOTE_DIR、OPENCODE_API_KEY（真 key）、PROBE_LEVEL（boot=就绪+黑名单/full=再加 verdict 透传，默认 full）、GOSS_BIN；
# 可覆盖：CANARY_CONTAINER、GOSS_FILE、PROBE_CASES_DIR、MIN_GOSS_CASES（manifest 同名变量由复用线 export）。
set -uo pipefail
: "${REMOTE_DIR:?REMOTE_DIR required}"
cd "$REMOTE_DIR" || exit 1
PROBE_LEVEL="${PROBE_LEVEL:-full}"
CANARY_CONTAINER="${CANARY_CONTAINER:-litellm-guard-canary}"
GOSS_BIN="${GOSS_BIN:-$REMOTE_DIR/.probe/goss}"
GOSS_FILE="${GOSS_FILE:-goss-gateway.yaml}"
PROBE_CASES_DIR="${PROBE_CASES_DIR:-$REMOTE_DIR/probe-cases}"
RESULT_DIR="${PROBE_RESULT_DIR:-$REMOTE_DIR/.probe-results}"
GOSS_TIMEOUT="${GOSS_TIMEOUT:-600}"
GOSS_RETRY_TIMEOUT="${GOSS_RETRY_TIMEOUT:-180s}"
GOSS_RETRY_SLEEP="${GOSS_RETRY_SLEEP:-5s}"
PROBE_CASE_TIMEOUT="${PROBE_CASE_TIMEOUT:-300}"
MIN_GOSS_CASES="${MIN_GOSS_CASES:-3}" # 现 3 条（http1+command2）；防删门禁，黑名单存在性另有专断
OPENCODE_API_KEY="${OPENCODE_API_KEY:-}"
JUNIT="$RESULT_DIR/goss-junit.xml"
VARS_FILE="$RESULT_DIR/goss-vars.yaml"
RESULTS_TSV="$RESULT_DIR/results.tsv"
DENIED_FILE="$RESULT_DIR/models-denied.json"
PASS=1

mkdir -p "$RESULT_DIR"
: > "$RESULTS_TSV"
record() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$RESULTS_TSV"; }
now_ms() { date +%s%3N; }
fmt_ms() { local ms="$1"; printf '%d.%03ds' $((ms / 1000)) $((ms % 1000)); }

echo "probe level: $PROBE_LEVEL"

CANARY_IP=""
for i in $(seq 1 12); do
  CANARY_IP="$(docker inspect "$CANARY_CONTAINER" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null || true)"
  [ -n "$CANARY_IP" ] && break
  echo "canary-ip#$i -> 未就绪（5s 后再试）"
  sleep 5
done
if [ -z "$CANARY_IP" ]; then
  echo "FAIL: 拿不到 canary 容器 IP（$CANARY_CONTAINER）"
  docker logs "$CANARY_CONTAINER" --tail 60 2>/dev/null || true
  exit 1
fi
echo "canary ip: $CANARY_IP (container=$CANARY_CONTAINER)"

PIN_GATEWAY="$(grep -oP 'image:\s*\K\S+@sha256:\S+' compose.yml | head -n1 || true)"
if [ -z "$PIN_GATEWAY" ]; then
  echo "FAIL: compose.yml 里没解出镜像 pin"; PASS=0
fi

DENIED_MODEL=""
SKIP_BLACKLIST=true
if ! docker cp "$CANARY_CONTAINER:/app/models-denied.json" "$DENIED_FILE" >/dev/null 2>&1; then
  echo "FAIL: 无法从 canary 读取 models-denied.json"; PASS=0
elif ! DENIED_MODEL="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d[0] if d else "")' "$DENIED_FILE")"; then
  echo "FAIL: models-denied.json 解析失败"; PASS=0
fi
if [ -n "$DENIED_MODEL" ]; then SKIP_BLACKLIST=false; fi
echo "blacklist: denied=$DENIED_MODEL skip=$SKIP_BLACKLIST"

{
  printf 'CANARY_IP: "%s"\n' "$CANARY_IP"
  printf 'CANARY_CONTAINER: "%s"\n' "$CANARY_CONTAINER"
  printf 'PIN_GATEWAY: "%s"\n' "$PIN_GATEWAY"
  printf 'DENIED_MODEL: "%s"\n' "$DENIED_MODEL"
  printf 'SKIP_BLACKLIST: %s\n' "$SKIP_BLACKLIST"
} > "$VARS_FILE"

GOSS_RC=127
GOSS_TESTS=0
GOSS_FAILED=0
GOSS_SKIPPED=0
GOSS_MS=0
echo "=== goss ==="
if [ ! -x "$GOSS_BIN" ] || [ ! -f "$GOSS_FILE" ]; then
  echo "FAIL: goss 运行件缺失（bin=$GOSS_BIN yaml=$GOSS_FILE）"
  record goss goss-run FAIL 0.000s
  PASS=0
else
  GOSS_START=$(now_ms)
  timeout "$GOSS_TIMEOUT" "$GOSS_BIN" -g "$GOSS_FILE" --vars "$VARS_FILE" \
    validate --format junit --retry-timeout "$GOSS_RETRY_TIMEOUT" --sleep "$GOSS_RETRY_SLEEP" \
    > "$JUNIT" 2> "$RESULT_DIR/goss.err"
  GOSS_RC=$?
  GOSS_MS=$(( $(now_ms) - GOSS_START ))
  if [ "$GOSS_RC" -ne 0 ] && [ -s "$RESULT_DIR/goss.err" ]; then tail -n 80 "$RESULT_DIR/goss.err"; fi

  PARSE="$(python3 - "$JUNIT" "$RESULTS_TSV" <<'PY'
import sys
import xml.etree.ElementTree as ET

junit, tsv = sys.argv[1], sys.argv[2]
try:
    with open(junit, encoding="utf-8") as fh:
        data = fh.read()
    start = data.rfind("<testsuite")
    end = data.find("</testsuite>", start)
    if start < 0 or end < 0:
        raise ValueError("no complete testsuite element")
    snippet = data[start:end + len("</testsuite>")]
    root = ET.fromstring(snippet)
    with open(junit, "w", encoding="utf-8") as fh:
        fh.write('<?xml version="1.0" encoding="UTF-8"?>\n' + snippet + "\n")
except Exception as exc:
    print(f"GOSS_PARSE_ERROR={exc}")
    raise SystemExit(2)

rows = []
failed = skipped = 0
for tc in root.findall(".//testcase"):
    name = tc.get("name", "?")
    secs = float(tc.get("time") or 0)
    failure = tc.find("failure")
    error = tc.find("error")
    skip = tc.find("skipped")
    if skip is not None:
        result = "SKIP"
        skipped += 1
    elif failure is not None or error is not None:
        result = "FAIL"
        failed += 1
        node = failure if failure is not None else error
        message = (node.text or "").strip()
        if message:
            print(f"GOSS-FAIL {name}: {message}", file=sys.stderr)
    else:
        result = "PASS"
    rows.append(("goss", name, result, f"{secs:.3f}s"))

with open(tsv, "a", encoding="utf-8") as fh:
    for row in rows:
        fh.write("\t".join(row) + "\n")

print(f"GOSS_TESTS={len(rows)}")
print(f"GOSS_FAILED={failed}")
print(f"GOSS_SKIPPED={skipped}")
PY
)"
  PARSE_RC=$?
  if [ "$PARSE_RC" -ne 0 ]; then
    echo "FAIL: goss junit 解析失败（rc=$PARSE_RC）"
    record goss goss-run FAIL "$(fmt_ms "$GOSS_MS")"
    PASS=0
  else
    while IFS='=' read -r k v; do
      case "$k" in
        GOSS_TESTS) GOSS_TESTS="$v" ;;
        GOSS_FAILED) GOSS_FAILED="$v" ;;
        GOSS_SKIPPED) GOSS_SKIPPED="$v" ;;
      esac
    done <<< "$PARSE"
  fi

  if [ "$GOSS_RC" -eq 124 ]; then
    echo "FAIL: goss 段 timeout ${GOSS_TIMEOUT}s"
  fi
  if [ "$GOSS_RC" -ne 0 ] || [ "$GOSS_FAILED" -ne 0 ]; then PASS=0; fi
  echo "goss: rc=$GOSS_RC tests=$GOSS_TESTS failed=$GOSS_FAILED skipped=$GOSS_SKIPPED duration=$(fmt_ms "$GOSS_MS") junit=$JUNIT"
fi

echo "=== probe-cases ==="
shopt -s nullglob
CASES=("$PROBE_CASES_DIR"/*.sh)
shopt -u nullglob
if [ "${#CASES[@]}" -eq 0 ]; then
  echo "SKIP probe-cases: 无 *.sh"
else
  export REMOTE_DIR CANARY_IP CANARY_CONTAINER PROBE_LEVEL OPENCODE_API_KEY
  for f in "${CASES[@]}"; do
    base="$(basename "$f" .sh)"
    CASE_START=$(now_ms)
    if timeout "$PROBE_CASE_TIMEOUT" bash "$f" > "$RESULT_DIR/probe-case-$base.log" 2>&1; then
      CASE_RC=0
      CASE_RESULT=PASS
    else
      CASE_RC=$?
      CASE_RESULT=FAIL
      PASS=0
    fi
    CASE_MS=$(( $(now_ms) - CASE_START ))
    echo "probe-case $base: $CASE_RESULT (rc=$CASE_RC, $(fmt_ms "$CASE_MS"))"
    if [ "$CASE_RC" -ne 0 ]; then tail -n 40 "$RESULT_DIR/probe-case-$base.log"; fi
    if [ "$CASE_RC" -eq 124 ]; then echo "FAIL: probe-case $base timeout ${PROBE_CASE_TIMEOUT}s"; fi
    record runner "probe-case:$base" "$CASE_RESULT" "$(fmt_ms "$CASE_MS")"
  done
fi

echo "=== baseline ==="
if [ "$GOSS_TESTS" -lt "$MIN_GOSS_CASES" ]; then
  echo "FAIL: goss 用例数 $GOSS_TESTS < 下限 $MIN_GOSS_CASES"; PASS=0
else
  echo "OK: goss 用例数 $GOSS_TESTS >= 下限 $MIN_GOSS_CASES"
fi
BL_PASS_COUNT="$(awk -F'\t' '$1 == "goss" && $2 ~ /blacklist/ && $3 == "PASS" {n++} END {print n+0}' "$RESULTS_TSV")"
if [ "$SKIP_BLACKLIST" = "false" ]; then
  if [ "$BL_PASS_COUNT" -eq 0 ]; then
    echo "FAIL: goss 结果缺黑名单 PASS 条目"; PASS=0
  else
    echo "OK: goss 结果含黑名单 PASS 条目 $BL_PASS_COUNT 条"
  fi
else
  echo "SKIP 黑名单底线: denied 名单为空（全放行）"
fi

echo "=== probe table ==="
python3 - "$RESULTS_TSV" <<'PY'
import sys
rows = []
try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        for line in fh:
            if line.strip():
                rows.append(line.rstrip("\n").split("\t"))
except FileNotFoundError:
    pass
header = ("SECTION", "NAME", "RESULT", "DURATION")
widths = [len(h) for h in header]
for row in rows:
    for i in range(4):
        widths[i] = max(widths[i], len(row[i] if i < len(row) else ""))
print("  ".join(h.ljust(widths[i]) for i, h in enumerate(header)))
print("  ".join("-" * w for w in widths))
for row in rows:
    print("  ".join((row[i] if i < len(row) else "").ljust(widths[i]) for i in range(4)))
PY

if [ "$PASS" -eq 1 ]; then
  echo "DETAIL OK"
  echo "PROBE OK"
  exit 0
fi
echo "FAIL: canary probe 未通过（junit: $JUNIT）"
exit 1
