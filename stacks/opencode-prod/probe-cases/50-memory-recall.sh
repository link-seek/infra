#!/bin/bash
# probe-cases/50-memory-recall.sh — 跨会话记忆召回（写 → 新会话 → 断言）。
# runner 契约：REMOTE_DIR/CANARY_CONTAINER/PROBE_LEVEL…；boot 级跳过（参 drain）。
# 门 = 会话 B 是否回显 marker；DB 行数只打日志，warn 不拦（防 infra 抖动误杀）。
# 模型调用要网关：无网关（img trial）则 SKIP，同 drain 条件；生产 canary 有网关必跑。
# marker 带 run 短号命名空间，可辨认；忘删靠批量清（忘 API 不稳定，不做自动删）。
set -uo pipefail

CASE=memory-recall
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
PASS=1
fail() { echo "FAIL: $1"; PASS=0; }

skip_case() { # $1=人话 $2=reason
  echo "SKIP $CASE: $1"
  echo "CASE-RESULT: SKIP $CASE reason=$2"
  exit 0
}

if [ "${PROBE_LEVEL:-full}" != "full" ]; then
  skip_case "PROBE_LEVEL=${PROBE_LEVEL:-}（full 才跑，boot 参 drain）" "probe-level-${PROBE_LEVEL:-unset}"
fi
: "${CANARY_CONTAINER:?CANARY_CONTAINER required}"
if ! docker inspect "$CANARY_CONTAINER" >/dev/null 2>&1; then
  echo "FAIL: canary 容器不存在：$CANARY_CONTAINER"
  echo "CASE-RESULT: FAIL $CASE reason=canary-missing"
  exit 1
fi

# 模型调用要网关：本机 :4000 不通则 SKIP（img trial 无网关，opencode run 必 hang；
# 同 drain 条件）。生产 canary 有网关，必跑；marker 命名空间隔离生产记忆。
if ! timeout 10 curl -s -m 5 -o /dev/null http://127.0.0.1:4000/v1/models; then
  skip_case "本机无网关（opencode run 必 hang；同 drain 条件，生产 canary 必跑）" "no-gateway"
fi

RUN_REF="${GITHUB_RUN_ID:-${GITHUB_RUN_NUMBER:-}}"
RUN_SHORT="$(printf '%s' "$RUN_REF" | tr -cd '0-9A-Za-z' | tail -c 9)"
if [ -z "$RUN_SHORT" ]; then
  RUN_SHORT="$(date -u +%Y%m%d%H%M%S)$$"
  RUN_SHORT="${RUN_SHORT: -9}"
fi
RUN_SHORT_L="$(printf '%s' "$RUN_SHORT" | tr '[:upper:]' '[:lower:]')"
MARKER="MEM-$RUN_SHORT"
echo "marker: $MARKER"

echo "=== session A（写） ==="
if timeout 90 docker exec "$CANARY_CONTAINER" opencode run \
    "记住探针标记 ${MARKER}，收到只回复：记住了" >"$TMP_DIR/a.out" 2>&1; then
  tail -n 20 "$TMP_DIR/a.out"
  if grep -q '记住了' "$TMP_DIR/a.out"; then
    echo "OK: session A 回「记住了」"
  else
    fail "session A 未回「记住了」"
  fi
else
  RC=$?
  tail -n 20 "$TMP_DIR/a.out"
  fail "session A 退出码 $RC"
fi

if [ "$PASS" = "1" ]; then
  sleep 6 # 给 auto-capture / 向量落盘留异步时间
  B_OK=0
  B_SEQ="$(date -u +%s)$$"
  for attempt in 1 2; do
    # --session 带一个不存在的新 id：opencode v2 会据此新建会话（不是继续 A）。
    B_SID="ses_mem${RUN_SHORT_L}${B_SEQ}${attempt}"
    echo "=== session B（新会话 $B_SID，第 $attempt 次） ==="
    if timeout 70 docker exec "$CANARY_CONTAINER" opencode run --session "$B_SID" \
        "探针标记 ${MARKER}是什么？只回复标记" >"$TMP_DIR/b.out" 2>&1; then
      tail -n 20 "$TMP_DIR/b.out"
      if grep -Fqi "$MARKER" "$TMP_DIR/b.out"; then
        echo "OK: 新会话召回 $MARKER"
        B_OK=1
        break
      fi
      echo "NOTE: 新会话未回显标记（attempt $attempt）"
    else
      RC=$?
      tail -n 20 "$TMP_DIR/b.out"
      echo "NOTE: 新会话退出码 $RC（attempt $attempt）"
    fi
    [ "$attempt" -lt 2 ] && sleep 8
  done
  [ "$B_OK" = "1" ] || fail "新会话 B 未召回探针标记"
fi

# DB 兜底：只打行数，任何失败都只是 WARN，不影响 recall 门。
memory_db_diag() {
  echo "=== memory DB（只记录行数，warn 不拦） ==="

  # 当前镜像的 L2：opencode-mem SQLite shard。
  local sqlite_out
  sqlite_out="$(timeout 10 docker exec "$CANARY_CONTAINER" python3 -c '
import glob, os, sqlite3
root = "/root/.local/share/opencode/opencode-mem"
files = sorted(glob.glob(os.path.join(root, "**", "*.db"), recursive=True))
if not files:
    print("opencode-mem: 无 shard 文件")
else:
    for f in files[:5]:
        try:
            con = sqlite3.connect("file:%s?mode=ro" % f, uri=True)
            tables = [r[0] for r in con.execute("select name from sqlite_master where type=\"table\"")]
            counts = []
            for t in tables[:8]:
                try:
                    n = con.execute("select count(*) from \"%s\"" % t).fetchone()[0]
                except Exception:
                    continue
                counts.append("%s=%d" % (t, n))
            print("%s: %s" % (os.path.basename(f), ", ".join(counts)))
            con.close()
        except Exception as exc:
            print("%s: read-fail (%s)" % (os.path.basename(f), exc))
    print("opencode-mem: files=%d" % len(files))
' 2>/dev/null || true)"
  if [ -n "$sqlite_out" ]; then
    while IFS= read -r line; do echo "memory-db: $line"; done <<< "$sqlite_out"
  else
    echo "WARN memory-db: opencode-mem SQLite 行数读取失败（warn 不拦）"
  fi

  # mem0 pg：容器名命中 mem0/postgres 才查；查不到只 WARN。
  local pg_names pg_name pg_out line
  pg_names="${MEM0_PG_CONTAINER:-$(timeout 5 docker ps --format '{{.Names}}' 2>/dev/null | grep -Ei '(mem0|graphiti).*(pg|postgres)|(pg|postgres).*(mem0|graphiti)' | head -n1 || true)}"
  if [ -z "$pg_names" ]; then
    echo "memory-db: mem0 pg: 未发现 mem0/graphiti Postgres 容器（跳过）"
  else
    while IFS= read -r pg_name; do
      [ -n "$pg_name" ] || continue
      # shellcheck disable=SC2016 # 单引号内是容器内 shell 展开，宿主不展开
      pg_out="$(timeout 10 docker exec "$pg_name" sh -c '
        command -v psql >/dev/null 2>&1 || exit 3
        user="${POSTGRES_USER:-${PGUSER:-postgres}}"
        db="${POSTGRES_DB:-${PGDATABASE:-postgres}}"
        export PGPASSWORD="${POSTGRES_PASSWORD:-${PGPASSWORD:-}}"
        psql -At -F "|" -U "$user" -d "$db" \
          -c "select relname, coalesce(n_live_tup, 0) from pg_stat_user_tables order by relname" 2>/dev/null
      ' 2>/dev/null || true)"
      if [ -n "$pg_out" ]; then
        while IFS= read -r line; do echo "memory-db: pg[$pg_name] $line"; done <<< "$pg_out"
      else
        echo "WARN memory-db: pg[$pg_name] 行数查询失败（表/凭证未知；warn 不拦）"
      fi
    done <<< "$pg_names"
  fi

  # graphiti：常见落地是 Neo4j，有 cypher-shell 才查节点数；否则 WARN。
  local neo_names neo_name neo_out
  neo_names="${GRAPHITI_CONTAINER:-$(timeout 5 docker ps --format '{{.Names}}' 2>/dev/null | grep -Ei 'graphiti|neo4j' | head -n1 || true)}"
  if [ -z "$neo_names" ]; then
    echo "memory-db: graphiti: 未发现 graphiti/neo4j 容器（跳过）"
  else
    while IFS= read -r neo_name; do
      [ -n "$neo_name" ] || continue
      # shellcheck disable=SC2016 # 单引号内是容器内 shell 展开，宿主不展开
      neo_out="$(timeout 10 docker exec "$neo_name" sh -c '
        command -v cypher-shell >/dev/null 2>&1 || exit 3
        auth="${NEO4J_AUTH:-neo4j/neo4j}"
        user="${auth%%/*}"
        pass="${auth#*/}"
        cypher-shell -u "$user" -p "$pass" --format plain \
          "MATCH (n) RETURN count(n) AS nodes" 2>/dev/null
      ' 2>/dev/null || true)"
      if [ -n "$neo_out" ]; then
        while IFS= read -r line; do echo "memory-db: graphiti[$neo_name] $line"; done <<< "$neo_out"
      else
        echo "WARN memory-db: graphiti[$neo_name] 行数查询失败（凭证/服务未知；warn 不拦）"
      fi
    done <<< "$neo_names"
  fi
}
memory_db_diag

if [ "$PASS" = "1" ]; then
  echo "CASE-RESULT: PASS $CASE marker=$MARKER"
  exit 0
fi
echo "CASE-RESULT: FAIL $CASE marker=$MARKER"
exit 1
