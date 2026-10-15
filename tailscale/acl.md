# Tailscale 意图

真规则在 Tailscale 管理面（ACL/tag 按控制台为准），仓里只记意图与节点表。

## 节点（2026-10-14 实测 `tailscale status`）

| 节点 | tailnet IP | 备注 |
|---|---|---|
| mesh-hw-21 | 100.91.222.51 | `tailscale serve` 只放 litellm :4000，tailnet-only，无 funnel |
| mesh-ali-gz | 100.85.128.116 | 公网入口机；Caddy → hw-21 走 tailnet（防火墙 LOG 取证） |
| mesh-hw-41 | 100.111.231.85 | — |
| mesh-oci-vpn | 100.103.182.112 | 出口节点（exit node） |
| mesh-xyc-pc | 100.69.220.112 | 个人 PC |
| mesh-yx-mac | 100.78.144.89 | macOS（偶尔离线） |

## CI 意图（二期收权，2026-10-15 落地）

- 部署流水线用一次性 auth key 加网（one-use，24h 过期 cap），短命用完即焚。
- 角色隔离，两个 tag 互不可达对方目标：
  - `tag:ci-trial` → 仅 `100.111.231.85:22`（1.41 试用）
  - `tag:ci-prod` → 仅 `100.91.222.51:22`（HW21 生产）
- key 与 secret 一一对应：`TAILSCALE_AUTH_KEY_TRIAL` / `TAILSCALE_AUTH_KEY_PROD`
 （旧共用 `TAILSCALE_AUTH_KEY` 待删）。runner flags：`--accept-routes=false
  --accept-dns=false`。出网（GitHub/ghcr/SWR）走 runner 本机直连，不经 tailnet，
  故无需其它放行。
- 笼子自证：两条 deploy workflow 上机前先做否定测试（连不该连的必须超时），
  否则 abort。Tailscale SSH 特性保持关闭，只走 OpenSSH 22。
- 旧 ali-gz:22 中转意图作废：新链直连目标机，不经入口机。
