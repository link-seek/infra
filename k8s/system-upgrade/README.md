# system-upgrade-controller（声明式 k3s 升级）

用 Rancher [system-upgrade-controller](https://github.com/rancher/system-upgrade-controller) 的 `Plan` CRD 管 k3s 升级。本目录是控制面 + RBAC + k3s Server/Agent 两个 Plan。

## 镜像（合并/放开前必须先镜像到 SWR）

`image-policy` 只认 SWR。本目录引用以下镜像，需先用 `docker-images` 的 `img-to-swr` 流水线镜像（与 `edge/registries/registries.yaml` 里 k3s-* 同模式）：

| 引用 | 上游 | 说明 |
|---|---|---|
| `.../link-seek/system-upgrade-controller:v0.20.1` | `rancher/system-upgrade-controller:v0.20.1` | 控制面 |
| `.../link-seek/kubectl:v1.30.3` | `rancher/kubectl:v1.30.3` | Job 里用的 kubectl |
| `.../link-seek/k3s-upgrade:v1.37.2-k3s1` | `rancher/k3s-upgrade:v1.37.2-k3s1` | Plan 升级 Job（tag 与 node/k3s-version 对应，`+`→`-`） |

镜像未就绪时**不要**放开 `clusters/k3s/apps-system-upgrade.yaml` 的 `suspend`，否则控制面会 ImagePullBackOff。

## 启用

1. 上述镜像进 SWR（public）。
2. 去掉 `clusters/k3s/apps-system-upgrade.yaml` 的 `spec.suspend: true`，合 PR。
3. 确认控制面起来：`kubectl -n system-upgrade get pods`。

## 升级流程（改版本）

1. 改 `node/k3s-version`。
2. 改本目录 `plans.yaml` 两个 Plan 的 `version`（**目前需与 k3s-version 手工同值**；后续可用 Flux postBuild 从 k3s-version 注入以消除这处同步）。
3. 确保对应 `k3s-upgrade:vX.Y.Z-k3s1` 已镜像到 SWR。
4. 合 PR → SUC 自动按 Plan 逐台 cordon/drain/升级/uncordon（server concurrency=1 保 quorum）。
5. 观察：`kubectl -n system-upgrade get plan,job`、`kubectl get nodes`。

## 回滚

改回 `node/k3s-version` + `plans.yaml` 的 version 到旧版本（同样要旧镜像在 SWR），再合 PR。
