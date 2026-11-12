#!/bin/sh
# k3s-sync-data：在 HW41 上跑（root），把 compose 卷数据搬到 .69 k3s 卷。单用户低峰操作。
# HW41 卷为 live 卷（prod 仍在跑）：打包瞬间可能有写入，操作前请确认无人会话；trial 侧已 scale 0，无写入。
# 用法：scripts/k3s-sync-data.sh（无参数，全 fail-closed）
set -eu

R69="ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@192.168.1.69"

# 0. 卷名 fail-closed（compose project 取目录名 opencode-prod-ali-gz）
WVOL="$(docker volume ls --format '{{.Name}}' | grep -x 'opencode-prod-ali-gz_prod-work' || true)"
DVOL="$(docker volume ls --format '{{.Name}}' | grep -x 'opencode-prod-ali-gz_prod-data' || true)"
[ -n "$WVOL" ] || { echo "FAIL: hw41 prod-work 卷名对不上"; docker volume ls | head -20; exit 1; }
[ -n "$DVOL" ] || { echo "FAIL: hw41 prod-data 卷名对不上"; docker volume ls | head -20; exit 1; }
# Mountpoint 动态取（HW41 docker 根在 /data/docker，不写死 /var/lib/docker）
WDIR="$(docker volume inspect -f '{{.Mountpoint}}' "$WVOL")"
DDIR="$(docker volume inspect -f '{{.Mountpoint}}' "$DVOL")"
[ -d "$WDIR" ] || { echo "FAIL: $WDIR 不在"; exit 1; }
[ -d "$DDIR" ] || { echo "FAIL: $DDIR 不在"; exit 1; }

# 1. k3s 停写（trial 无流量也停，防 untar 竞态）
$R69 "kubectl -n opencode scale deploy/opencode --replicas=0"
$R69 "kubectl -n opencode wait --for=delete pod -l app=opencode --timeout=180s"

# 2. HW41 打包（Mountpoint 直读，不另拉镜像）
du -sh "$WDIR" "$DDIR"
tar czf /tmp/k3s-sync-work.tgz -C "$WDIR" .
tar czf /tmp/k3s-sync-data.tgz -C "$DDIR" .
ls -lh /tmp/k3s-sync-work.tgz /tmp/k3s-sync-data.tgz

# 3. 传 .69（同机房 LAN，HW41 直传）
scp -o BatchMode=yes -o StrictHostKeyChecking=no /tmp/k3s-sync-work.tgz /tmp/k3s-sync-data.tgz root@192.168.1.69:/tmp/

# 4. .69 目标路径（local-path PV 用 spec.local.path；hostPath 为空是正常的）
$R69 "kubectl -n opencode get pvc"
WPVNAME="$($R69 "kubectl -n opencode get pvc prod-work -o jsonpath={.spec.volumeName}")"
DPVNAME="$($R69 "kubectl -n opencode get pvc prod-data -o jsonpath={.spec.volumeName}")"
echo "pv: work=$WPVNAME data=$DPVNAME"
[ -n "$WPVNAME" ] || { echo "FAIL: 取不到 work 卷名"; exit 1; }
[ -n "$DPVNAME" ] || { echo "FAIL: 取不到 data 卷名"; exit 1; }
WPATH="$($R69 "kubectl get pv $WPVNAME -o jsonpath={.spec.local.path}")"
DPATH="$($R69 "kubectl get pv $DPVNAME -o jsonpath={.spec.local.path}")"
# jsonpath 为空则 sed 兜底（local-path PV 的 path 行唯一）
[ -n "$WPATH" ] || WPATH="$($R69 "kubectl get pv $WPVNAME -o json" | sed -n 's/^[[:space:]]*"path": "\(.*\)".*/\1/p' | head -1)"
[ -n "$DPATH" ] || DPATH="$($R69 "kubectl get pv $DPVNAME -o json" | sed -n 's/^[[:space:]]*"path": "\(.*\)".*/\1/p' | head -1)"
echo "volpath: work=[$WPATH] data=[$DPATH]"
WPATH="$($R69 "kubectl get pv $WPVNAME -o jsonpath='{.spec.hostPath.path}'")"
DPATH="$($R69 "kubectl get pv $DPVNAME -o jsonpath='{.spec.hostPath.path}'")"
[ -n "$WPATH" ] || { echo "FAIL: 取不到 work 卷路径"; exit 1; }
[ -n "$DPATH" ] || { echo "FAIL: 取不到 data 卷路径"; exit 1; }
echo "work: $WPATH data: $DPATH"

# 5. .69 现状备份（trial 渣，留回退）→ 清空 → 解包
$R69 "tar czf /tmp/k3s-vol-backup-work.tgz -C '$WPATH' . && tar czf /tmp/k3s-vol-backup-data.tgz -C '$DPATH' . && ls -lh /tmp/k3s-vol-backup-*.tgz"
$R69 "find '$WPATH' -mindepth 1 -delete && find '$DPATH' -mindepth 1 -delete"
$R69 "tar xzf /tmp/k3s-sync-work.tgz -C '$WPATH' && tar xzf /tmp/k3s-sync-data.tgz -C '$DPATH' && du -sh '$WPATH' '$DPATH'"

# 6. 拉起 + rollout（深验证走 k3s-apply apply）
$R69 "kubectl -n opencode scale deploy/opencode --replicas=1 && kubectl -n opencode rollout status deploy/opencode --timeout=900s"

echo SYNC-OK
