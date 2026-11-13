#!/bin/sh
# HW21 定时任务：从各 k3s server 拉最新本地快照 → 传 OBS north-9 → 两端保留。
# 用法：k3s-etcd-fetch-upload.sh
# 前置：k3s 各节点已开 etcd-snapshot-schedule-cron（本地快照）；本机 obsutil 已配好 north-9 可写凭证。
set -euo pipefail
BUCKET=linkseek-k3s-etcd
KEEP_LOCAL=28
KEEP_OBS=14
# HW21 默认 endpoint 是 north-4；备份桶在 north-9：临时切换，用完必还原（trap 兜底）。
CFG=/root/.obsutilconfig
BAK="$(mktemp /tmp/.obsutilconfig.bak.XXXXXX)"
cp "$CFG" "$BAK"
sed -i s#obs.cn-north-4.myhuaweicloud.com#obs.cn-north-9.myhuaweicloud.com# "$CFG"
restore_cfg() { cp "$BAK" "$CFG"; rm -f "$BAK"; }
trap restore_cfg EXIT
for IP in 192.168.1.69 192.168.1.41; do
  NAME="$(ssh -n -o BatchMode=yes -o StrictHostKeyChecking=no root@$IP 'hostname' | tr -d '\r\n ')"
  [ -n "$NAME" ] || { echo "FAIL: $IP 不可达"; exit 1; }
  echo "== $NAME($IP) =="
  LATEST="$(ssh -n -o BatchMode=yes -o StrictHostKeyChecking=no root@$IP 'ls -t /var/lib/rancher/k3s/server/db/snapshots/ 2>/dev/null | grep -E "^(etcd-snapshot|on-demand)-" | head -1' | tr -d '\r\n ')"
  [ -n "$LATEST" ] || { echo "no snapshot yet on $NAME, skip"; continue; }
  TMP="/tmp/etcd-$NAME-latest"
  scp -o BatchMode=yes -o StrictHostKeyChecking=no "root@$IP:/var/lib/rancher/k3s/server/db/snapshots/$LATEST" "$TMP"
  DEST="obs://$BUCKET/etcd-auto/$NAME/$LATEST"
  # 直接传（幂等覆盖；obsutil 存在性判定不可靠：ls 空 key 也 exit 0 且回显自带 key 名）
  obsutil cp "$TMP" "$DEST" >/dev/null 2>&1 || { echo "FAIL: upload $LATEST"; rm -f "$TMP"; exit 1; }
  echo "uploaded: $LATEST"
  rm -f "$TMP"
  # OBS 端每节点只留最新 KEEP_OBS 个
  DEL="$(obsutil ls "obs://$BUCKET/etcd-auto/$NAME/" 2>/dev/null | grep -oE '(etcd-snapshot|on-demand)-[^ /]*' | sort -r | tail -n +"$((KEEP_OBS + 1))" || true)"
  for f in $DEL; do obsutil rm "obs://$BUCKET/etcd-auto/$NAME/$f" >/dev/null 2>&1 || true; echo "pruned obs: $f"; done
  # 本地只留最近 KEEP_LOCAL 个（k3s retention 兜底，双保险）
  ssh -n -o BatchMode=yes -o StrictHostKeyChecking=no root@$IP \
    "ls -t /var/lib/rancher/k3s/server/db/snapshots/ 2>/dev/null | grep -E '^(etcd-snapshot|on-demand)-' | tail -n +$((KEEP_LOCAL + 1)) | while read -r f; do rm -f \"/var/lib/rancher/k3s/server/db/snapshots/\$f\"; done; true"
done
echo FETCH-UPLOAD-OK
