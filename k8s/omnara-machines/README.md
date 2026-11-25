# omnara-machines（Omnara kubernetes provider 机器池，上游 omnara-ai/omnara#878）

Omnara 独立部署，远端调用本集群：`provider_config` 放 API URL + CA，token 放 Omnara 侧 org secret。
禁 in-cluster credential、禁 kubeconfig。

## 落地后取凭证（token 不进仓）

```sh
# API URL（内网：tailnet 下用对应 tailnet IP；docker 独立 Omnara 需先确认到 6443 可达）
kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'
kubectl -n kube-system get secret $(kubectl -n kube-system get sa ci-deployer -o jsonpath='{.secrets[0].name}') -o jsonpath='{.data.ca\.crt}' | base64 -d | head -3
# 机器池 SA 长效 token（k8s 自动填）
kubectl -n omnara-machines get secret omnara-machines-token -o jsonpath='{.data.token}' | base64 -d | head -c 20
```

Omnara 侧连通检查应区分过期/非法（provider `connection check` 逻辑，见上游评论）。

## 约束

- ns enforce `baseline`（restricted 会拒绝机器 Pod，见 #878）；只 warn restricted。
- 机器 Pod 模板（provider 代码侧定死）：`shareProcessNamespace:true`、`automountServiceAccountToken:false`、drop `NET_RAW`、`RuntimeDefault`、`restartPolicy:Never`、request==limit、可选 `runtimeClassName`。
- 磁盘：LimitRange 默认 1Gi、上限 10Gi；总数：Quota pods 20（按需调大）。
- 出站：NetworkPolicy 默认封 `169.254.169.254/32`，其余放行；flannel 下是否真强制需联调验证。
- `podPidsLimit`、drain `--force` 为 provider 文档页建议项，不改节点配置。
