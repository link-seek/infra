# Kyverno（#317 item7）

- `install.yaml`：Kyverno **v1.20.0** 官方安装清单；镜像已重写为 SWR
  （`reg.kyverno.io` 国内不可达，先从 ghcr 镜像进 SWR，见 `docker-images/images/mirror.yaml`）。
- 镜像当前为 **SWR 私有**，故 `kyverno` ns 需要 `swr-pull`（各 Deployment 已挂 imagePullSecrets）：
  ```
  kubectl -n kube-system get secret swr-pull -o yaml \
    | sed 's/namespace: kube-system/namespace: kyverno/' | kubectl apply -f -
  ```
  （与 `scripts/k3s-restore-drill.sh` 同法；Secret 不进仓。）
- 策略在 `k8s/kyverno-policies`（`dependsOn: kyverno`），**Enforce**，作用域=受管 app 命名空间
  （opencode-* / litellm / erpnext / cognee-trial / nfs / reloader）。
- 升级 Kyverno：改 `install.yaml` 版本 + `images/mirror.yaml` 对应镜像，发 PR。
