# link-seek/infra — 组织基础设施唯一源

本仓是 link-seek 所有基础设施配置的唯一入口：**线上长什么样、怎么变，全在这里**。
规则三条：

1. 按系统/节点分目录存放，每次变更只动自己的目录。
2. 真值（IP、主机名、端口、DNS 内容）直接进 git，commit diff 即审计底账；
   真钥匙（Tailscale/SSH/Cloudflare）一律进 org secrets，永不进仓。
3. 部署只从 `main` 分支触发（PR 合并），回滚 = revert 对应目录。

## 目录

```
docs/topology.md          # 组织总图：机器/网络/域名/证书一览（保持最新）
docs/<system>.md          # 每个系统一张分图
docs/repo-inventory.md    # 组织仓库清单与规整计划（专项，见 Discussions）
edge/caddy/<node>/        # 入口机 Caddyfile，按节点分目录
dns/records.yaml          # 全组织 DNS 声明（权威）；cloudflare.md 为说明
tailscale/acl.md          # 节点表 + tag/ACL 意图（真规则在 Tailscale 管理面）
stacks/<system>/          # 各系统 topology 级引用，不搬业务仓代码
.github/workflows/       # 一个栈一个 workflow，paths filter 隔离
```

## 分工：商家 vs 快递（2026-10-18，与 docker-images 仓 README 同源）

- **商家（`link-seek/docker-images` 的 `bake-*`）对产品负责**：业务逻辑（guard、passthrough、auth、重试、默认配置、插件 bake）全部进镜像，digest 即行为版本号。
- **快递（本仓 `deliver-*`）只对运输负责**：compose pin digest + env 引用 → `up` 即部署，无业务逻辑，不碰内容。**回滚 = 换 digest 发 PR**，git 历史即备份。
- **门（`secret-hygiene` / `schema-stacks`）只验货**：核密钥卫生与运单形状，不碰值。已删 `render-check`（2026-10-24：只核名字对齐，执行层断裂时照样全绿，虚假安全感； wiring 问题由发货时 fail-closed + 试送门兜底）。
- 命名：`bake-*` = 烘焙镜像，`deliver-*` = 送达目标机，`deliver-promote-*` = 只办 tag 晋升手续（retag 不 rebuild）。`img-preflight.yml` 文件名冻结为跨仓契约（bake 线按文件名调用），显示名是 `deliver-preflight`。

## 部署（快递线）

| workflow | 触发 | 动作 |
|---|---|---|
| `deliver-caddy.yml` | `edge/caddy/**` 变 + `main` | ephemeral runner → tailnet → 目标节点 reload + 验证 |
| `dns-apply.yml` | 手动（`workflow_dispatch`） | 按 `records.yaml` 对账 Cloudflare（二期启用） |

## 规整专项

组织仓库偏多、边界靠人脑记的问题，跟踪见
[Discussions：组织仓库规整](https://github.com/link-seek/infra/discussions)，
清单模板见 `docs/repo-inventory.md`。
