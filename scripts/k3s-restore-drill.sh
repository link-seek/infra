#!/bin/sh
# k3s-restore-drill：在 HW41 上跑（root），目标 .69。只碰 scratch（opencode-restore），生产 ns 不动。
# 1) 控制面备份：datastore 快照 + token 离机到 HW41 /root/k3s-drill（600，永不进仓）。
# 2) 数据恢复：备份 tgz（sync-data 产物）解到 scratch 卷。
# 3) 验证：文件数对账 + 全部 *.db integrity_check。
# 4) 成功删 scratch ns；失败保留现场。
# 前置：/tmp/k3s-sync-work.tgz + data.tgz 在 .69（缺失则先跑 sync-data）。
set -eu

R69="ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@192.168.1.69"
BKDIR=/root/k3s-drill
mkdir -p "$BKDIR" && chmod 700 "$BKDIR"

# 0. 备份存在性（fail-closed）
$R69 "test -f /tmp/k3s-sync-work.tgz && test -f /tmp/k3s-sync-data.tgz" || { echo "FAIL: .69 缺备份 tgz，先跑 sync-data"; exit 1; }

# 1. 控制面备份（类型自适应；token 不打日志）
if $R69 "test -d /var/lib/rancher/k3s/server/db/etcd"; then
  echo "datastore: etcd"
  $R69 "k3s etcd-snapshot save --name drill && ls -t /var/lib/rancher/k3s/server/db/snapshots/ | head -3"
  SNAP="$($R69 "ls -t /var/lib/rancher/k3s/server/db/snapshots/* | head -1")"
  scp -o BatchMode=yes -o StrictHostKeyChecking=no "root@192.168.1.69:$SNAP" "$BKDIR/"
else
  echo "datastore: sqlite（单节点默认）"
  $R69 "mkdir -p /tmp/k3s-drill-db && cp -a /var/lib/rancher/k3s/server/db/. /tmp/k3s-drill-db/ && du -sh /tmp/k3s-drill-db"
  scp -o BatchMode=yes -o StrictHostKeyChecking=no -r root@192.168.1.69:/tmp/k3s-drill-db "$BKDIR/"
fi
$R69 "cat /var/lib/rancher/k3s/server/token" > "$BKDIR/token" 2>/dev/null
chmod 600 "$BKDIR/token"
[ -s "$BKDIR/token" ] || { echo "FAIL: token 取回为空"; exit 1; }
echo "control-plane backup ok: $(ls "$BKDIR" | tr '\n' ' ')"

# 2. scratch 恢复（幂等：先清）
$R69 "kubectl delete ns opencode-restore --ignore-not-found && kubectl wait --for=delete ns/opencode-restore --timeout=120s" 2>/dev/null || true
$R69 "kubectl apply -f /tmp/k3s-restore-ns.yaml && kubectl apply -f /tmp/k3s-restore-pvc.yaml && kubectl apply -f /tmp/k3s-restore-consumer.yaml"
if ! $R69 "kubectl -n opencode-restore wait --for=condition=Ready pod/restore-consumer --timeout=180s"; then
  $R69 "kubectl -n opencode-restore get pvc,pods; kubectl -n opencode-restore describe pod restore-consumer | tail -20"
  echo "FAIL: consumer Pod 不 Ready（上为现场）"; exit 1
fi
RWPV="$($R69 "kubectl -n opencode-restore get pvc restore-work -o jsonpath={.spec.volumeName}")"
RDPV="$($R69 "kubectl -n opencode-restore get pvc restore-data -o jsonpath={.spec.volumeName}")"
RWPATH="$($R69 "kubectl get pv $RWPV -o jsonpath={.spec.local.path}")"
RDPATH="$($R69 "kubectl get pv $RDPV -o jsonpath={.spec.local.path}")"
[ -n "$RWPATH" ] || RWPATH="$($R69 "kubectl get pv $RWPV -o json" | sed -n 's/^[[:space:]]*"path": "\(.*\)".*/\1/p' | head -1)"
[ -n "$RDPATH" ] || RDPATH="$($R69 "kubectl get pv $RDPV -o json" | sed -n 's/^[[:space:]]*"path": "\(.*\)".*/\1/p' | head -1)"
[ -n "$RWPATH" ] && [ -n "$RDPATH" ] || { echo "FAIL: scratch 卷路径为空"; exit 1; }
echo "scratch: work=$RWPATH data=$RDPATH"
$R69 "tar xzf /tmp/k3s-sync-work.tgz -C '$RWPATH' && tar xzf /tmp/k3s-sync-data.tgz -C '$RDPATH'"
LIVE_WPV="$($R69 "kubectl -n opencode get pvc prod-work -o jsonpath={.spec.volumeName}")"
LIVE_DPV="$($R69 "kubectl -n opencode get pvc prod-data -o jsonpath={.spec.volumeName}")"
LIVE_WPATH="$($R69 "kubectl get pv $LIVE_WPV -o jsonpath={.spec.local.path}")"
LIVE_DPATH="$($R69 "kubectl get pv $LIVE_DPV -o jsonpath={.spec.local.path}")"
[ -n "$LIVE_WPATH" ] || LIVE_WPATH="$($R69 "kubectl get pv $LIVE_WPV -o json" | sed -n 's/^[[:space:]]*"path": "\(.*\)".*/\1/p' | head -1)"
[ -n "$LIVE_DPATH" ] || LIVE_DPATH="$($R69 "kubectl get pv $LIVE_DPV -o json" | sed -n 's/^[[:space:]]*"path": "\(.*\)".*/\1/p' | head -1)"
LIVE_WN="$($R69 "find '$LIVE_WPATH' | wc -l" | tr -d '[:space:]')"
RST_WN="$($R69 "find '$RWPATH' | wc -l" | tr -d '[:space:]')"
LIVE_DN="$($R69 "find '$LIVE_DPATH' | wc -l" | tr -d '[:space:]')"
RST_DN="$($R69 "find '$RDPATH' | wc -l" | tr -d '[:space:]')"
echo "files: live_work=$LIVE_WN rst_work=$RST_WN live_data=$LIVE_DN rst_data=$RST_DN"
[ "$RST_WN" -ge $((LIVE_WN * 9 / 10)) ] || { echo "FAIL: 恢复 work 文件数不足"; exit 1; }
[ "$RST_DN" -ge $((LIVE_DN * 9 / 10)) ] || { echo "FAIL: 恢复 data 文件数不足"; exit 1; }

# 3. sqlite 完整性（.69 须有 python3；EulerOS 自带，缺失则 fail）
$R69 "command -v python3" >/dev/null || { echo "FAIL: .69 无 python3"; exit 1; }
$R69 "python3 - '$RDPATH'" <<'PYEOF' || { echo "FAIL: sqlite integrity"; exit 1; }
import sys, glob, os, sqlite3
root = sys.argv[1]
files = sorted(glob.glob(os.path.join(root, "**", "*.db"), recursive=True))
print("db files=%d" % len(files))
bad = 0
for f in files:
    try:
        con = sqlite3.connect("file:%s?mode=ro" % f, uri=True)
        r = con.execute("pragma integrity_check").fetchone()[0]
        print("%s: %s" % (os.path.basename(f), r))
        if r != "ok":
            bad += 1
        con.close()
    except Exception as exc:
        print("%s: read-fail %s" % (os.path.basename(f), exc))
        bad += 1
sys.exit(1 if bad else 0)
PYEOF

# 4. 清理 scratch（成功才删；失败保留现场）
$R69 "kubectl delete ns opencode-restore --ignore-not-found"
echo DRILL-OK
