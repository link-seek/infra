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

## 部署

| workflow | 触发 | 动作 |
|---|---|---|
| `deploy-caddy.yml` | `edge/caddy/**` 变 + `main` | ephemeral runner → tailnet → 目标节点 reload + 验证 |
| `dns-apply.yml` | 手动（`workflow_dispatch`） | 按 `records.yaml` 对账 Cloudflare（二期启用） |

## 规整专项

组织仓库偏多、边界靠人脑记的问题，跟踪见
[Discussions：组织仓库规整](https://github.com/link-seek/infra/discussions)，
清单模板见 `docs/repo-inventory.md`。
