# link-seek/infra — 组织基础设施唯一源

本仓是 link-seek 所有基础设施配置的唯一入口：**线上长什么样、怎么变，全在这里**。
规则三条：

1. 按系统/节点分目录存放，每次变更只动自己的目录。
2. 真值（IP、主机名、端口、DNS 内容）直接进 git，commit diff 即审计底账；
   真钥匙（Tailscale/SSH/Cloudflare）一律进 org secrets，永不进仓。
3. 生产部署永远手动点火：改仓（合 PR、改配置、改流水线）不触发任何部署；
   发货 = 人手动 dispatch 对应 `deliver-*`（digest/tag 可选，默认 stable）。
   回滚 = revert 对应目录 + 手动再发一次。

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
- **门（`secret-hygiene` / `render-check` 等）只验货**：核密钥卫生与键集合，不碰值。
- 命名：`bake-*` = 烘焙镜像，`deliver-*` = 送达目标机，`deliver-promote-*` = 只办 tag 晋升手续（retag 不 rebuild）。`img-preflight.yml` 文件名冻结为跨仓契约（bake 线按文件名调用），显示名是 `deliver-preflight`。

## 部署（快递线：全部手动 dispatch，改仓不自动发）

| workflow | 手动点火 | 动作 |
|---|---|---|
| `deliver-litellm-gateway.yml` | Actions → deliver-litellm-gateway → Run（digest 默认 stable） | 蓝绿：canary 探针绿才切流 |
| `deliver-opencode-prod.yml` | Actions → deliver-opencode-prod → Run（digest 默认 stable） | 蓝绿 + 失败自动回滚（旧镜像留本地） |
| `deliver-opendesign.yml` | 同上，输入 `CUTOVER` 才执行 | 切流 OD |
| `deliver-caddy.yml` | 同上 | ephemeral runner → tailnet → 目标节点 reload + 验证 |
| `deliver-cloudflared.yml` | 同上（挑空闲时间，有十几秒闪断） | 备份 → 只换 ingress 段 → restart → 验证，失败回滚 |
| `dns-apply.yml` | 同上（默认 dry-run 只打印） | 按 `records.yaml` 对账 Cloudflare（二期启用） |
| `deliver-promote-*.yml` | 同上（输已测 digest） | 只打 tag + 回写 pin，不发货；发生产再手动点上面对应项 |

## 规整专项

组织仓库偏多、边界靠人脑记的问题，跟踪见
[Discussions：组织仓库规整](https://github.com/link-seek/infra/discussions)，
清单模板见 `docs/repo-inventory.md`。
