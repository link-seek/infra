# Backlog：节点不可变化（Talos / CoreOS）迁移

> 状态：**Backlog（暂不实施）** ｜ 关联：k3s 节点漂移治理（B 方案已落地，见 `k3s-node-config` / `k3s-edge-repair` / runbook §4）
> 决策记录：2026-11-28，网关 503 事故复盘后确定「先上 B（幂等 reconcile+告警），A 留作重建窗口启动」。

## 背景

本集群 = 5 节点多云 k3s（3× 华为云 server/etcd + edge agent：ali-gz 公网入口、vm-proxy 东京出口），
flannel VXLAN over Tailscale（`flannel-iface: tailscale0`），工作负载 Flux/GitOps 管理，节点配置由
`node/node-config.yaml` 声明 + `.github/workflows/k3s-node-config.yml` 巡检。

2026-11-28 事故：有人带外（out-of-band）为同步 token 手改 `vm-proxy` 的 `k3s-agent.service`，
丢了 ExecStart 续行符 `\` → systemd 丢弃 `--node-ip/--flannel-iface` → flannel 走 ens3、跨云断 →
`egress-proxy`(Squid) 解析不了 CoreDNS → 业务 503。属「节点可漂移、且漂移能静默变故障」这一类问题的典型。

B 方案（本次）已覆盖：unit 实际解析校验、L7 探针、失败自动开 issue、agent 幂等重装。
但 B 本质仍是「可变节点 + 收敛修复」；**要根除漂移，需要不可变节点（A）**。

## 为什么现在不做 A（结论）

A 的本质是**重建**而非改造：Talos/CoreOS 自带 OS，无法原地转换，**每台节点都要重新置备一次**；
且 k3s 与 Talos 不能混在同一集群。对现有 5 节点、含 3× etcd 控制面与有状态负载（erpnext/mariadb、
infisical/pg、NFS-PVC、opencode 数据）而言，这是一次「并行建新集群 → 迁工作负载 → 退役旧集群」的
数周级工程，迁移风险（etcd quorum、数据搬迁、多云+Tailscale 非标组合）显著高于收益。故**只在不需
额外成本的重建窗口顺风车做**。

## 启动条件（满足任一即评估启动 A）

1. **OS 生命周期到期 / 需大版本重装**（本来就要重建节点）；
2. **大规模扩容或换云**（新增一批节点）；
3. **节点漂移类事故频发**（B 的告警持续出现，人工修复成本上升）；
4. 团队愿意接受 API 驱动的运维范式（无 SSH/shell，走 machine config）。

## 最小可行路径（若启动）

1. **PoC（1 台无状态 edge）**：以 Talos 起一台 edge 节点，接入新集群，验证 Tailscale 底层 +
   flannel/VXLAN（或改用 Talos KubeSpan，需评估与现有 tailnet 的关系）。
2. **并行新集群**：Talos 起新控制面（3 节点）+ 新 edge，Flux 接管工作负载。
3. **迁工作负载**：先无状态（opencode/omnara/web），再有状态（用备份/快照迁移 PVC；erpnext、
   infisical/pg 单独窗口）。
4. **切流量 → 退役旧 k3s 集群**。
5. **回收 `link-seek/infra`**：`node-config`/`edge-join`/`k3s-node-config` 迁移为 Talos machine config
   或 CAPI 引导；更新 runbook。

## 风险清单

- etcd quorum / 控制面迁移；有状态数据搬迁；NFS/PVC 归属；
- Talos KubeSpan 与现有 Tailscale underlay 的取舍（ACL、路由、MTU）；
- 运维范式切换（无 SSH）带来的排障成本；CI（现依赖 SSH + get.k3s.io）需重写。

## 非目标

- 不在本 backlog 内做任何线上改动；不混跑 k3s+Talos 同集群。
