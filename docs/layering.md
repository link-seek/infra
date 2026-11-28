# 分层映射：组件归属 / 失败模式 / HA

> 用途：新增或搬迁组件时，先在这里找到它该在哪一层。判断依据不是"技术类型"，而是
> **它挂了会影响谁**：影响集群存活 → 集群层；只影响某些应用 → 应用层；描述 agent 能做什么 → 边界层。
> 只读审计结论，2026-11-28 核对线上副本数后写成。

## 三条判据（按顺序）

1. **集群层**：挂了会导致节点 NotReady、API 不可写、调度/网络/存储/证书整体失效、无法自愈。
   该层只放"集群存活必需"，且必须评估 HA —— 单副本 + fail-closed 的组合等于全集群单点。
2. **应用层**：只服务特定业务负载。作用域必须限定在应用命名空间；失败半径=该应用不可用。
3. **边界层**：描述"agent 能做什么"。优先用 RBAC（硬边界），策略引擎只做兜底，不能替代 RBAC。

## 集群层（挂了=集群受损）

| 组件 | 作用 | 失败模式 | HA |
|---|---|---|---|
| k3s server ×3（etcd 内嵌） | 控制面 + etcd | 1 台故障仍可写（3 节点 quorum） | 是（3 副本） |
| flannel / tailscale underlay | Pod 跨节点网络 | 节点仍 Ready 但跨节点 Pod 不通（见 runbook §1） | 无状态，可重启恢复 |
| CoreDNS | 集群内 DNS | 全集群 DNS 解析失败 | 2 副本（kube-system） |
| Traefik（edge/internal） | 入口 / 内部 ingress | 外部或内部入口不可用 | 单副本（edge 节点 hostNetwork） |
| local-path / NFS provisioner | 存储供给 | 新 PVC 无法绑定；已有卷不受影响 | 单副本 |
| etcd-backup CronJob | 每 6h 快照到 OBS | 备份断档（不影响运行） | 定时任务 |
| Flux（source/kustomize/helm/notification） | GitOps 对账 | 不再自动同步；线上维持现状 | 单副本（控制面） |
| Infisical + operator | Secret 供给 | 新 Pod 起不来/Secret 不更新 | 单副本 + 自带 PG/Redis |
| Kyverno（admission/background/reports/cleanup） | 准入策略引擎 | **fail-closed 时全集群写失败**（2026-11-27 事故） | admission 2 副本 + PDB，拓扑分散 |
| system-upgrade-controller | 节点升级编排 | 不影响运行，升级暂停 | 单副本 |
| ci-deployer（SA + ClusterRole） | CI 的部署身份 | CI 无法部署 | 身份对象，无副本概念 |

## 应用层（挂了=该应用不可用）

| 组件 | 作用 | 失败模式 | HA |
|---|---|---|---|
| litellm | LLM 网关 | 依赖它的应用无法推理 | 单副本 |
| egress-proxy（squid @ vm-proxy） | L7 出口代理 | 需出海的应用请求失败 | 单副本 |
| opencode-{xieyucheng,yingxin,team} | agent 实例 | 对应实例不可用（不影响别人） | 单副本（按人） |
| cognee + token-broker | 记忆后端 | 记忆读写失败，会话本身可用 | 单副本 |
| erpnext 全家桶 | 业务应用 | 该业务不可用 | 单副本 |
| omnara / omnara-machines | 业务应用 | 该业务不可用 | 单副本 |
| opencode-data | 数据卷/初始化 | 相关应用数据不可用 | 单副本 |
| reloader | Secret 变更触发 rollout | Secret 更新后 Pod 不自动重启 | 单副本 |

**reloader 归属说明**：被三个 opencode Deployment 使用（`reloader.stakater.com/auto=true`），
属于应用支撑组件；放在"底座"目录只是打包便利，语义上服务应用层。当前在用的组件不搬。

## 边界层（agent 能力边界）

| 机制 | 作用 | 失败模式 | 备注 |
|---|---|---|---|
| RBAC（SA/ClusterRole/Binding） | 硬边界：agent 能读写什么 | 配错=越权或不可用 | 首选手段，最小权限 |
| Kyverno 镜像三策略 | 兜底：镜像来源/标签/digest | 误报=部署受阻（不是集群受损） | 作用域限定受管 ns 的 Pod |
| AGENTS.md 提示词约束 | 软边界：行为约定 | 越线需人工确认 | 不能当作安全边界 |

## 分层纪律（从 2026-11-27 事故得出）

1. 集群层只放存活必需；应用策略的作用域=应用命名空间；集群级 catch-all 必须单独过 blast-radius 评审。
2. 同一策略引擎上的新 policy 必须沿用该引擎的变更纪律（Audit → 观察 → Deny）。
3. agent 边界不新建集群级硬控制：RBAC + 提示词；越线先告知人。
4. 组件迁移只有在"归属错误导致了实际故障或风险"时才做；纯搬家不做。
