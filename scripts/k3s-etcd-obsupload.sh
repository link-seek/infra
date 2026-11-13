#!/bin/sh
# etcd 本地快照上传 OBS + 保留最近 N 份（跑在 k3s server 上，由 cron 每小时触发）。
# 用法：k3s-etcd-obsupload.sh [BUCKET] [KEEP]
# 前提：k3s 已配 etcd-snapshot-schedule-cron（本地快照）；obsutil 已装且配好凭证。
set -euo pipefail
BUCKET="${1:-linkseek-k3s-etcd}"
KEEP="${2:-14}"
NODE="$(hostname -s 2>/dev/null || hostname)"
SRC_DIR="/var/lib/rancher/k3s/server/db/snapshots"
DST="obs://${BUCKET}/etcd-auto/${NODE}/"
NEWEST="$(ls -t "$SRC_DIR" 2>/dev/null | grep -E '^(etcd-snapshot|on-demand)-' | head -1 || true)"
[ -n "$NEWEST" ] || { echo "no local snapshot yet"; exit 0; }
echo "upload: $NEWEST"
obsutil cp "$SRC_DIR/$NEWEST" "$DST" >/dev/null 2>&1 || { echo "FAIL: upload"; exit 1; }
echo "prune: keep newest $KEEP in $DST"
DEL="$(obsutil ls "$DST" 2>/dev/null | grep -oE '(etcd-snapshot|on-demand)-[^ /]*' | sort -r | tail -n +"$((KEEP + 1))" || true)"
for f in $DEL; do
  obsutil rm "${DST}${f}" >/dev/null 2>&1 || true
  echo "pruned: $f"
done
echo "UPLOAD-OK: $NEWEST"
