# Tailscale 意图

正本是 `tailscale/policy.hujson`（控制台导出的原样）；改动先改这个文件、走 PR，
下发/核对只用 `.github/workflows/ts-acl-apply.yml`（手动 dispatch：verify / apply / tag-device）。
本文件只记意图与节点表，规则细节看 policy.hujson。

## 节点（2026-10-14 实测 `tailscale status`）

| 节点 | tailnet IP | tag | 备注 |
|---|---|---|---|
| mesh-hw-21 | 100.91.222.51 | `tag:mesh` + `tag:prod` | 生产。`tailscale serve` 只放 litellm :4000，tailnet-only，无 funnel |
| mesh-ali-gz | 100.85.128.116 | `tag:mesh` | 公网入口机；Caddy → hw-21 走 tailnet |
| mesh-hw-41 | 100.111.231.85 | `tag:mesh` | 普通机器，**不再是 trial 靶子** |
| mesh-oci-vpn | 100.103.182.112 | `tag:connector` | 出口节点（exit node） |
| mesh-xyc-pc | 100.69.220.112 | `tag:mesh` | 个人 PC |
| mesh-yx-mac | 100.78.144.89 | `tag:mesh` | macOS（偶尔离线） |
| opencode-prod（容器） | 自动分配 | `tag:opencode` | userspace tailscaled，hostname 固定 `opencode-prod`，随容器起停 |
| CI 临时节点 | — | `tag:ci` | 部署方 + 靶子，ephemeral，随 run 焚毁 |

## 身份与可达性意图（2026-10-27 更新）

- 身份只有三类 tag：
  - `tag:ci`：CI 起的**每一个**节点（部署方 + 临时靶子），mint key 时带 `tags:["tag:ci"]`。
  - `tag:prod`：常驻生产机（hw-21）。
  - `tag:opencode`：opencode-prod 容器（deploy 现场 mint reusable+ephemeral+90d key）。
- 可达性（grants；过渡期保留 2244 给旧 key 通路，切完 TS SSH 验证后删）：
  - `tag:ci` → `tag:prod` : 22, 2244
  - `tag:ci` → `tag:ci`   : 22, 2244
  - `tag:ci` → `100.91.222.51` : 4000（trial 直调生产网关；不开 ssh）
  - `tag:opencode` → `.21/.41`（100.91.222.51 / 100.111.231.85）: 22
  - `tag:mesh` → `tag:opencode` : 22
  - `tag:ci` → `tag:opencode` : 22（仅 trial 可见性：netmap 按 ACL 过滤，无此条探针看不到 canary；不配 ssh 规则，CI 不能 SSH 进 canary，探针走 docker exec）
- Tailscale SSH（ssh 段）：
  - `tag:ci` → `tag:prod` root：生产部署
  - `tag:ci` → `tag:ci` root：部署到临时靶子（靶子 join 时带 `--ssh`）
  - `tag:opencode` → `.21/.41` root：容器出站（与旧 1.21/1.41 等价；ssh dst 写 `tag:mesh`，
    由上面的 grant 收窄到这两台，二者交集生效）
  - `tag:mesh` → `tag:opencode` root：人登容器排障
  - `tag:mesh` → `tag:mesh` root：人登机器
- 已删 `autogroup:member` → `tag:mesh` / `tag:connector`：未打 tag 的节点不再能 root 进任何机器。
  依据：2026-10-25 实测，任意未打 tag 的 CI 节点可直接 `tailscale ssh root@hw-21` 成功。
  人的设备都是 `tag:mesh`，走 `tag:mesh → tag:mesh`，能力不变。
- 旧 `tag:ci-trial` / `tag:ci-prod`、`TAILSCALE_AUTH_KEY_TRIAL` / `_PROD` 一并作废：
  trial 靶子由 CI 现建现焚，hw-41 只是普通 `tag:mesh` 机器，不再承担 trial 角色。
- 笼子自证：deliver 线在上机前仍做否定测试（连不该连的必须超时），否则 abort。
- 出网（GitHub/ghcr/SWR）走 runner 本机直连，不经 tailnet，故 CI 节点无需其它放行。
- 破窗：OpenSSH 2244 + 个人 key 保留（人用）；CI 不再持有生产私钥。
- 旧 ali-gz:22 中转意图作废：新链直连目标机，不经入口机。
