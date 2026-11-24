#!/usr/bin/env bash
# #317 adopt-list：用 kubeconform（社区维护）对所有 kustomize 目录做 k8s schema 校验。
# 渲染用 kubectl kustomize；CRD 类资源用 -ignore-missing-schemas 跳过（不 false-red）。
set -euo pipefail
KUBECTL="${KUBECTL:-kubectl}"
KUBECONFORM="${KUBECONFORM:-kubeconform}"
fail=0
while IFS= read -r d; do
  if ! "$KUBECTL" kustomize "$d" > /tmp/render.yaml 2> /tmp/render.err; then
    echo "[RENDERFAIL] $d"; head -3 /tmp/render.err; fail=1; continue
  fi
  if ! "$KUBECONFORM" -ignore-missing-schemas -summary - < /tmp/render.yaml; then
    echo "[SCHEMAFAIL] $d"; fail=1
  fi
done < <(find k8s clusters -name kustomization.yaml -printf '%h\n' | sort -u)
[ "$fail" = "0" ] && echo "KUBECONFORM-OK"
exit "$fail"
