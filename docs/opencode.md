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

- `opencode-prod`：tools 镜像 v2.0.27（browser sidecar PR#6 已含），`0.0.0.0:4097`
  （公网有暴露但实测零流量；加固项：收紧到 127.0.0.1 + tailnet）。
- `opencode-browser`：chrome-cjk，`BROWSER_CDP_URL=http://172.17.0.1:9222`（静态网桥 IP，
  headless-shell 拒非 IP Host 头，服务名直连不可用）。
- `opencode-net`：bridge 172.19.0.0/16。注意：重建导致子网变化时同步改 litellm publish。
- `litellm-guard`：4000 发布于 127.0.0.1 + 172.17.0.1 + 172.19.0.1（多机共用，零新增对外面）。
  inspect 备份：`/root/litellm-guard/inspect-backup-20261013.json`。
- tailscale serve：只放 litellm :4000，tailnet-only，未开 funnel。

## 密钥（源头均为 sops 密文 xieyucheng123/opencode-secrets）

`SMTP_*`（163，465 隐式 TLS）、`MAIL_DEFAULT_TO=xieyucheng@outlook.com`、
`OPENCODE_SERVER_PASSWORD`、`GH_TOKEN`、`HCLOUD_AK/SK`、`LITELLM_API_KEY`、
`CLOUDFLARE_API_TOKEN`（管 DNS）、`SSH_PRIVATE_KEY_B64`（容器钥匙，
SSH_TARGETS 四台：.21/.41/0001 EIP/0002 EIP；001/002 非常驻开机）。

## 待办

- [ ] `opencode.xieyucheng.top` 上线：Caddy 加新块 + 旧名 301（本仓 workflow 落地）
- [ ] DNS：`opencode` A → 120，删 WAF 死 CNAME
- [ ] 4097 监听收紧（127.0.0.1 + tailnet）
