# opencode 系统分图

## 公网链路

```
Internet
 └─ hw21-opencode.xieyucheng.top (A → 120.77.76.20)
    └─ mesh-ali-gz Caddy（TLS 终结，见 edge/caddy/mesh-ali-gz/Caddyfile）
       └─ reverse_proxy 100.91.222.51:4097（走 tailnet，不经过公网）
          └─ hw21 opencode-prod（见 xieyucheng123/opencode docker/compose.yml）
```

设计：edge TLS termination + private backend（标准做法，见 2026-10-14 结论）。

## hw21 本机（/root/stacks/opencode-prod）

- `opencode-prod`：tools 镜像（browser sidecar PR#6 已含），`0.0.0.0:4097`
  （公网有暴露但实测零流量；加固项：收紧到 127.0.0.1 + tailnet）。
- `opencode-prod` 容器自己跑 userspace `tailscaled`（无 tun / NET_ADMIN），
  hostname `opencode-prod`，tag `tag:opencode`；入网 key 由 deliver 现场 mint 成
  `.env` 的 `TS_JOIN_KEY`（reusable+ephemeral+90d），启动时 `tailscale up --ssh`。
  `tailscale-state` 卷持久化 node key，重建不改名；canary 用 `opencode-prod-canary`。
- `opencode-browser`：chrome-cjk，`BROWSER_CDP_URL=http://172.17.0.1:9222`（静态网桥 IP，
  headless-shell 拒非 IP Host 头，服务名直连不可用）。
- `opencode-net`：bridge 172.19.0.0/16。注意：重建导致子网变化时同步改 litellm publish。
- `litellm-guard`：4000 发布于 127.0.0.1 + 172.17.0.1 + 172.19.0.1（多机共用，零新增对外面）。
  inspect 备份：`/root/litellm-guard/inspect-backup-20261013.json`。
- tailscale serve：只放 litellm :4000，tailnet-only，未开 funnel。

## 密钥（源头均为 sops 密文 xieyucheng123/opencode-secrets）

`SMTP_*`（163，465 隐式 TLS）、`MAIL_DEFAULT_TO=xieyucheng@outlook.com`、
`OPENCODE_SERVER_PASSWORD`、`GH_TOKEN`、`HCLOUD_AK/SK`、`LITELLM_API_KEY`、
`CLOUDFLARE_API_TOKEN`（管 DNS）、`TS_JOIN_KEY`（deliver 现场 mint 的容器入网 key）。
容器不再持有静态 SSH 私钥；`SSH_TARGETS` 仅作文档/排障提示，语义为 tailnet hostname
（`mesh-hw-21 mesh-hw-41`）。

## 容器 SSH（TS-only）

```sh
# 人进容器排障（tag:mesh -> tag:opencode）
tailscale ssh root@opencode-prod

# 容器出去（tag:opencode -> .21/.41）
docker exec opencode-prod tailscale ssh root@mesh-hw-21 'hostname'
docker exec opencode-prod tailscale ssh root@mesh-hw-41 'hostname'
```

旧 `ssh`/`ssh-keyscan`/authorized_keys 通路已退役；出站请用 `tailscale ssh`。

## 待办

- [ ] 验证双向 TS SSH 后：删 `PROD_SSH_PRIVATE_KEY_B64` secret，清 `.21/.41` 旧 key `authorized_keys`（#43）
- [ ] `opencode.xieyucheng.top` 上线：Caddy 加新块 + 旧名 301（本仓 workflow 落地）
- [ ] DNS：`opencode` A → 120，删 WAF 死 CNAME
- [ ] 4097 监听收紧（127.0.0.1 + tailnet）

## mesh-ali-gz 本机栈（opencode.yingxin.net.cn）

- 入口：`opencode.yingxin.net.cn` → mesh-ali-gz Caddy → `127.0.0.1:4097`（本机 opencode-prod-ali-gz）。
- 栈目录：`stacks/opencode-prod-ali-gz/`（复用 opencode-prod 模板，卷/命名独立）。
- 网关：tailnet `mesh-hw-21:4000`（本机无 litellm-guard）。
