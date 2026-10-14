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

## CI 意图（二期收权）

- 部署流水线用一次性 auth key 加网，节点打 `tag:ci`，短命用完即焚。
- ACL 目标：`tag:ci` 只放行 → mesh-ali-gz:22（部署）与公网 443（验证），
  不放行 hw21 其它端口。一期先用普通 key 跑通，二期收权。
