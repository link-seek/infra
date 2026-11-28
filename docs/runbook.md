# Runbook — 集群故障处置

> 配套：`README.md`（真值与部署模型）、`.github/workflows/k3s-node-config.yml`（节点/数据面漂移巡检）。
> 标注约定：**【根治】** = 回到声明态；**【临时】** = 只恢复可用性，必须后续根治。

## 1. flannel.1 数据面丢失（路由/邻居/FDB 全丢，节点仍 Ready）

### 症状

- 节点 `kubectl get nodes` 仍 `Ready`，但跨节点 Pod 网络不通（同节点正常）
- `ip route show dev flannel.1` 没有远端 PodCIDR 路由（正常应为「节点数-1」条 `10.42.X.0/24 via 10.42.X.0 onlink`）
- `ip neigh show dev flannel.1` 全为 `INCOMPLETE`/`FAILED`（正常应为 `PERMANENT`）
- `bridge fdb show dev flannel.1` 没有远端 VTEP 条目（正常应为「节点数-1」条）
- `ip -s link show flannel.1`：TX packets 为 0，或 `tx_dropped` 持续增长
- k3s 日志序列：`external interface tailscale0 not found, retrying in 30s` → `VXLAN device flannel.1 recreated successfully`

根因：underlay（tailscale0）重建触发 flannel 重建设备，但路由/邻居/FDB 只由远端 lease 事件写入；重建不产生 lease 变化，表项永久缺失。上游：k3s#12436、k3s#14142、flannel#2247；修复 PR k3s#14086 backport 到 1.33.13+。

### 诊断阶梯（逐层，先便宜后昂贵）

```bash
# 1) 节点与接口
kubectl get nodes -o wide
ip -d link show flannel.1            # 期望 "local <tailnet-ip> dev tailscale0"
ip -s link show flannel.1            # 看 TX packets / tx_dropped

# 2) 表项（本次事故的判定点）
ip route show dev flannel.1
ip neigh show dev flannel.1
bridge fdb show dev flannel.1
ip rule show                          # 期望 5210/5230/5250/5270 四条 tailscale 规则

# 3) underlay
tailscale status
ping -c2 <peer-tailnet-ip>

# 4) 报文（分层定位：入向有没有、出向有没有、ARP 有没有回）
tcpdump -ni tailscale0 -c 20 'udp port 8472'   # 应能看到远端 VXLAN 入向
tcpdump -ni flannel.1  -c 20                    # 本地出向是否发出
tcpdump -ni flannel.1  -c 20 arp                 # 事故现场：request 有、reply 无
```

一键巡检（含以上数据面检查）：GitHub Actions → `k3s-node-config` → `mode=verify`，或本地按 workflow 内脚本只读执行。

### 恢复

**【根治】** 重启该节点的 k3s（server 用 `k3s`，edge agent 用 `k3s-agent`）：

```bash
systemctl restart k3s        # 或 k3s-agent
# 等 30–60s，然后复核
ip route show dev flannel.1 | wc -l          # 节点数-1
ip neigh show dev flannel.1                  # PERMANENT
bridge fdb show dev flannel.1 | wc -l        # 节点数-1
ip -s link show flannel.1                    # TX 增长、tx_dropped 不再增长
```

已知限制（2026-11-28 实测，v1.37.2+k3s1）：重启会按租约重放路由/neigh/FDB，**但 ARP 广播解析仍可能不可用**。
验证方法：删掉一条远端 neigh 再发流量，若邻居变成 `INCOMPLETE`、跨节点流量中断，说明 ARP 仍坏，
必须把静态邻居加回来——此时下面的 workaround 仍是必需的，不能只靠重启。


重启前确认该节点不是唯一承载关键单副本组件的位置（如 Kyverno admission 副本、ingress），必要时先迁移。

**【临时】** 静态邻居兜底（只恢复单播转发，不修 ARP 泛洪）：

```bash
# MAC 来源：任一健康节点上 `bridge fdb show dev flannel.1` 的 "dst <peer-tailnet-ip>" 对应 MAC
ip neigh replace 10.42.0.0 lladdr da:3f:00:1e:17:f5 dev flannel.1 nud permanent
ip neigh replace 10.42.1.0 lladdr 8e:71:f3:04:1a:33 dev flannel.1 nud permanent
ip neigh replace 10.42.2.0 lladdr e6:22:e6:67:40:9d dev flannel.1 nud permanent
ip neigh replace 10.42.5.0 lladdr 56:44:95:03:80:f9 dev flannel.1 nud permanent
```

注意：MAC 与 PodCIDR 租约绑定，节点重建后会变；该命令是**临时措施**，必须在下一个维护窗口重启 k3s 并删除这些静态条目（`ip neigh del <ip> dev flannel.1`）。

## 2. Break-glass 序列（控制面/准入故障时）

本次事故实践（Kyverno catch-all webhook 拒绝 kubelet 写入，Flux 无法自愈）：

1. **冻结对账**：`flux suspend kustomization <name>`（不删对象，避免 Flux 把带外修改回滚）
2. **带外止血**：节点 SSH / 云控制台进入；必要时同时 suspend 受影响的 Kustomization
3. **修通道**：直接改线上对象（`kubectl patch/delete`）恢复控制面写入
4. **回灌仓库**：改动写进 PR（worktree 从 `origin/main` 新建），根因修复走正常评审
5. **恢复对账**：`flux resume kustomization <name>` + `kubectl annotate ... reconcile.fluxcd.io/requestedAt`
6. **验证收尾**：verify workflow 全绿 + 业务探针；把时间线与处置写进 issue

铁律：break-glass 期间改的每一笔都必须回灌仓库，否则下次对账会覆盖或产生静默漂移。

## 3. admission policy 变更纪律（明文规则）

- **Audit 先行，硬门槛**：新增/修改 ValidatingPolicy 必须先以 `Audit`（report-only）上线，观察至少一个业务周期（一周），确认 PolicyReports 无高危误报后才可切 `Deny`。跳过观察期属于越线操作。
- **匹配范围必须匹配失败半径**：集群级 / `*/*` catch-all 必须单独做 blast-radius 评审，并显式豁免系统身份（`system:nodes`、`system:kube-controller-manager`、`system:kube-scheduler`、CCM）。准入层只做兜底，**不能替代 RBAC**；能用 RBAC 表达的边界不要用 webhook。
- **可用性前置**：`failurePolicy: Fail` 的策略必须评估副本数/PDB/拓扑分散；单副本又是 fail-closed 的组合等于全集群写单点。
- **变更前后核对**：

```bash
kubectl get vpol
kubectl get validatingwebhookconfiguration -o json | jq -r '.items[].webhooks[].name'   # 不应出现 catch-all
kubectl get policyreports -A | awk 'NR>1 {p+=$5; f+=$6; e+=$7; w+=$8} END {print p,f,e,w}'
```

## 4. 节点 unit 漂移（ExecStart 续行符丢失 / 参数被 systemd 丢弃）

### 症状

- `k3s-node-config` 定时 verify 报 `DRIFT-FLANNEL`（`flannel.1 local 10.0.0.x dev ens3` 而非 `... dev tailscale0`）、`DRIFT-MTU`，甚至 `DRIFT-MISSING node-ip/flannel-iface`。
- 节点 `Ready`，但跨云 Pod 网络 / 集群 DNS 不通；该节点上的 `hostNetwork` 组件（如 `egress-proxy`）解析不了 CoreDNS → 业务 503（Squid `ERR_DNS_FAIL`）。
- `systemctl show k3s-agent -p ExecStart --value` 里**看不到** `--node-ip/--flannel-iface`——因为 unit 的 `--token` 行尾漏了续行符 `\`，其后参数整段被 systemd 丢弃。

### 根因

带外（out-of-band）**手改** `/etc/systemd/system/k3s-agent.service`（如为同步 token）改坏了多行 ExecStart 的续行符。**不在声明式流水线内**（`link-seek/infra` 无此步骤）。

### 诊断

```bash
systemctl show k3s-agent -p ExecStart --value | grep -oE -- '--(node-ip|flannel-iface)[= ][0-9a-zA-Z./]+'  # 期望两条都在
systemctl cat k3s-agent | sed -n '/^ExecStart=/,$p'                                                       # 逐行确认续行以 \ 结尾
ip -d link show flannel.1 | grep -o 'local [0-9.]* dev [a-z0-9]*'                                          # 期望 local <tailnet-ip> dev tailscale0
```

### 恢复（【根治】）

- **agent**：走 `k3s-edge-repair`（`workflow_dispatch`：`node_hostname` + `agent_ip` + `confirm_hostname`），用官方安装器按 `node/node-config.yaml` 幂等重装、重建 ExecStart。**不要手改 unit。**
- **server**：走 `k3s-node-config`（`mode=apply`）合并 `config.yaml`，必要时 `restart=yes`。
- 修完再跑 `k3s-node-config`（`mode=verify`）确认 `NODE-OK`。
- 若只是 flannel 数据面表项丢失（unit 正常、仅 route/neigh/FDB 空）→ 参见 §1（重启 `k3s`/`k3s-agent`）。**注意：unit 本身坏了时，单纯重启无效。**

### 纪律（明文规则）

- **禁止手改** `/etc/systemd/system/k3s.service`、`/etc/systemd/system/k3s-agent.service` 的 `ExecStart`。
- 所有节点级变更必须走：`k3s-node-config`（apply，server）或 `k3s-edge-repair` / `k3s-join-edge`（agent 重装）。
- token 轮换**不得**通过改 unit 同步；agent 入簇只应使用短时 bootstrap token（`k3s token create`），**不把 server token 写进 agent unit**。

