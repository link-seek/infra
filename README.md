# link-seek/infra — 组织基础设施唯一源

本仓是 link-seek 基础设施（k3s 底座 + 入口 + DNS + 网络 + 出口）的唯一声明源：**线上长什么样、怎么变，全在这里**。**文档只此一份 README**（旧的分散文档已删除）；真值以仓内声明式配置为准。

## 原则

1. **真值进 git**：节点参数、路由、DNS、ACL、镜像白名单等以仓内声明文件为准，commit diff 即审计底账。
2. **密钥不进仓**：Tailscale / SSH / Cloudflare / 云 AK 等走 GitHub org secrets；应用运行时 Secret（`litellm-env`、`opencode-*-env`、`browserless-env`、`erpnext` 等）走自建 Infisical（`k8s/infisical`），由 Infisical Operator 按 `k8s/infisical-apps/*` 的 `InfisicalSecret` 同步成 k8s Secret，仓库不留密文。
3. **GitOps**：合 PR → CI 打包 OCI 制品 → 集群 Flux 自动对账（见下）。改仓即部署。

## 部署模型（Gitless GitOps）

- `flux-artifact.yml`：main 每次 push 把本仓打成 Flux OCI 制品，推到 `swr.cn-north-9.myhuaweicloud.com/link-seek/infra-manifests`（避免 Flux 直连 github.com 被污染/超时）。
- 集群内 `flux-system` 的 `OCIRepository` 拉该制品；`clusters/k3s/apps-*.yaml` 每个是一个 Flux `Kustomization`：
  - **底座**（`sourceRef: flux-system`，清单在本仓 `k8s/`）：`egress`、`traefik-edge`、`ci-deployer`、`reloader`。
  - **应用层**（`sourceRef: docker-images`，清单在 `link-seek/docker-images` 仓 `k8s/<app>`）：`litellm`、`opencode-xieyucheng`、`opencode-yingxin`、`opencode-team`、`erpnext`、`cognee-trial`。
- 合并即生效（Flux 5m 轮询；可手动 `flux reconcile`/annotation 加速）。**回滚 = revert + 再合**。
- 加速对账：`kubectl -n flux-system annotate ocirepository flux-system reconcile.fluxcd.io/requestedAt="$(date -u +%FT%TZ)" --overwrite`

## 集群（k3s）

5 节点：3 台华为云 control-plane+etcd（hw21/41/69），2 台 edge（ali-gz 公网入口、vm-proxy 东京出口）。全节点 flannel 走 **Tailscale underlay**（`flannel-iface=tailscale0`，`flannel.1 MTU=1230`）。

| 节点 | 内网 / tailnet | 角色 |
|---|---|---|
| mesh-hw-21 (hw21) | 192.168.1.21 / 100.100.246.95 | control-plane + etcd |
| mesh-hw-41 | 192.168.1.41 / 100.73.182.4 | control-plane + etcd |
| mesh-hw-69 | 192.168.1.69 / 100.93.119.21 | control-plane + etcd |
| mesh-ali-gz | 120.77.76.20 / 100.85.128.116 | edge：公网入口（Traefik 接管 80/443，宿主 Caddy 已退役） |
| vm-proxy | — / 100.73.221.121 | edge：东京出口（egress squid） |

- 节点级参数（`node-ip` / `node-external-ip` / `flannel-iface` / MTU）真相：**`node/node-config.yaml`**（workflow `k3s-node-config.yml` 做 verify/apply 漂移检查）。
- etcd 每 6h 打快照直传 OBS 华北9 桶（CronJob，`k3s-etcd-obs.yml`）；恢复演练 `k3s-restore-drill.yml`。

## 入口 / DNS

- **入口**：Traefik 在 `mesh-ali-gz` 以 hostNetwork 直接接管 80/443，用 `IngressRoute` 按 Host 分发到各 Service；TLS 用 IngressRoute 自带的 TLS secret。配置见 `k8s/traefik-edge`。
- **域名**（Cloudflare 托管，声明源 `iac/terraform/cloudflare/dns.tf`，由 Terraform 对账；`iac-cloudflare.yml` 跑 plan、人工确认再 apply）：
  - `opencode.xieyucheng.top` → Traefik → `opencode-xieyucheng`
  - `opencode.yingxin.net.cn` → Traefik → `opencode-yingxin`
  - `erp.xieyucheng.top` → `erpnext`
  - `litellm.linkseek.net.cn` → `litellm` 网关

## 网络 / ACL

- ACL/tag 真相：**`acl/policy.hujson`**（workflow `ts-acl-apply.yml` 下发）。
- 节点入网/加节点：`k3s-join-*.yml`、`k3s-join-edge.yml`。

## 出口（egress）

`k8s/egress`：Squid L7 CONNECT 出口代理，钉 `vm-proxy`（hostNetwork），供 litellm 出海（`HTTPS_PROXY`）。细节见 `k8s/egress/README.md`。

## 目录

```
clusters/k3s/            # Flux：flux-system + 各应用 Kustomization（apps-*.yaml）+ docker-images 源（git-docker-images.yaml）
k8s/                     # 底座清单：egress / traefik-edge / ci-deployer / reloader / etcd-backup / tailscale-operator / restore
node/node-config.yaml     # 节点参数真相（k3s-node-config.yml）
iac/terraform/cloudflare/ # Cloudflare DNS/zone 声明（Terraform）——唯一 DNS 源（iac-cloudflare.yml）
acl/policy.hujson  # tailnet ACL 真相（ts-acl-apply.yml）
edge/registries/         # 镜像仓映射 + 境外镜像 allowlist（image-policy.yml）
edge/cloudflare/         # Cloudflare edge 规则声明（cf-edge-apply.yml）
scripts/                 # apply/verify/迁移脚本
.github/workflows/       # 打包 / 对账 / 校验 / 节点运维
```

## 应用层归属

业务 pod（litellm / opencode* / erpnext / cognee 等）的 Deployment/Service/IngressRoute 与镜像，都在 `link-seek/docker-images` 仓的 `k8s/<app>`；本仓 `clusters/k3s/apps-*.yaml` 只声明 Flux 对账关系。本仓**只留底座**，不碰业务 pod 内容。

## 运维 / 变更

- 看状态：`kubectl -n flux-system get kustomizations`、`kubectl get pods -A`
- k3s 升级：走 `k8s/system-upgrade`（system-upgrade-controller + Plan），流程见该目录 README；版本真相是 `node/k3s-version`。
- 节点漂移巡检：手动 dispatch `k3s-node-config.yml`（verify）；DNS 对账：`iac-cloudflare.yml` mode=plan（只读）；ACL：`ts-acl-apply.yml`
- 校验门：`schema-stacks.yml`（清单形状）、`secret-hygiene.yml`（密钥卫生）、`image-policy.yml`（境外镜像 digest 白名单）
