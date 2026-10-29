#!/usr/bin/env bash
# 现场 render .env（终态：dotenv 包只活内存，不再读存量 B64）。
#
# 用法：
#   render-dotenv.sh --map <env-sources.conf> --example <.env.example> [--check-only] [--out <file>]
#
# map 行格式（# 注释，空行忽略）：
#   KEY=secret:ENV_SUFFIX    # 值从环境变量 S_<ENV_SUFFIX> 取（调用方从 secrets 导出）
#   KEY=literal:VALUE        # 非密值，直接写进 map（进 git，禁真值；VALUE 为 __TODO__ 表示待填）
#
# 铁律：日志只打印键名，永不打印值。空值 secret 直接失败（只报键名）。
set -euo pipefail

MAP=""; EXAMPLE=""; CHECK_ONLY=0; OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --map) MAP="$2"; shift 2;;
    --example) EXAMPLE="$2"; shift 2;;
    --check-only) CHECK_ONLY=1; shift;;
    --out) OUT="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
[ -n "$MAP" ] && [ -n "$EXAMPLE" ] || { echo "need --map and --example" >&2; exit 2; }
[ "$CHECK_ONLY" = 1 ] || [ -n "$OUT" ] || { echo "need --out unless --check-only" >&2; exit 2; }

# --- 解析 map：KEY -> KIND:REF（重复键报错） ---
MAP_KEYS="$(mktemp)"; MAP_BODY="$(mktemp)"; trap 'rm -f "$MAP_KEYS" "$MAP_BODY"' EXIT
awk '
  /^[[:space:]]*#/ { next }
  /^[[:space:]]*$/ { next }
  {
    line=$0; sub(/^[[:space:]]+/, "", line)
    n=index(line, "=")
    if (n==0) { print "BADLINE: " line > "/dev/stderr"; exit 1 }
    k=substr(line,1,n-1); v=substr(line,n+1)
    gsub(/[[:space:]]+$/, "", k)
    if (k=="") { print "BADLINE(empty key): " line > "/dev/stderr"; exit 1 }
    print k "\t" v
  }
' "$MAP" > "$MAP_BODY"
cut -f1 "$MAP_BODY" | sort > "$MAP_KEYS"
DUPES="$(uniq -d "$MAP_KEYS" | tr '\n' ' ')"
[ -z "$DUPES" ] || { echo "DUPLICATE_KEYS: $DUPES" >&2; exit 1; }

# --- .env.example 键集合 ---
EXP_KEYS="$(mktemp)"; trap 'rm -f "$MAP_KEYS" "$MAP_BODY" "$EXP_KEYS"' EXIT
grep -v '^[[:space:]]*#' "$EXAMPLE" | grep '=' | cut -d= -f1 | sed 's/[[:space:]]//g' | grep -v '^$' | sort -u > "$EXP_KEYS"

MISSING="$(comm -13 "$MAP_KEYS" "$EXP_KEYS" | tr '\n' ' ')"
EXTRA="$(comm -23 "$MAP_KEYS" "$EXP_KEYS" | tr '\n' ' ')"
FAIL=0
[ -z "$MISSING" ] || { echo "MISSING_IN_MAP: $MISSING" >&2; FAIL=1; }
[ -z "$EXTRA" ] || { echo "EXTRA_IN_MAP(not in .env.example): $EXTRA" >&2; FAIL=1; }

# --- __TODO__ 字面量（待填的非密值） ---
TODOS="$(awk -F'\t' '$2=="literal:__TODO__" { print $1 }' "$MAP_BODY" | tr '\n' ' ')"
[ -z "$TODOS" ] || { echo "TODO_LITERAL(unfilled non-secret): $TODOS" >&2; FAIL=1; }

if [ "$CHECK_ONLY" = 1 ]; then
  [ "$FAIL" = 0 ] && echo "CHECK OK: $(wc -l < "$MAP_KEYS" | tr -d ' ') keys, map == .env.example"
  exit "$FAIL"
fi
[ "$FAIL" = 0 ] || exit 1

# --- render（umask 收紧，值不进日志） ---
umask 077
: > "$OUT"
while IFS="$(printf '\t')" read -r k v; do
  case "$v" in
    secret:*)
      suffix="${v#secret:}"
      # 间接取值：S_<SUFFIX>
      S_VAR="S_$suffix"; val="${!S_VAR:-}"
      if [ -z "$val" ]; then echo "EMPTY_SECRET: $k (from S_$suffix)" >&2; exit 1; fi
      printf '%s=%s\n' "$k" "$val" >> "$OUT"
      echo "rendered $k from secret"
      ;;
    literal:*)
      # 显式 S_<KEY> 覆盖优先于 literal（trial 等分支用）；未提供则用 map 里的字面量。
      S_KEY_VAR="S_$k"; S_KEY_VAL="${!S_KEY_VAR:-}"
      if [ -n "$S_KEY_VAL" ]; then
        printf '%s=%s\n' "$k" "$S_KEY_VAL" >> "$OUT"
        echo "rendered $k from S_ override"
      else
        printf '%s=%s\n' "$k" "${v#literal:}" >> "$OUT"
        echo "rendered $k from literal"
      fi
      ;;
    *)
      echo "BAD_SOURCE(need secret:/literal:): $k" >&2; exit 1;;
  esac
done < "$MAP_BODY"
echo "wrote $(wc -l < "$OUT" | tr -d ' ') keys to $OUT (values never logged)"
