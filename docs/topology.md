# link-seek 基础设施总图

> 唯一源声明：本文件与各分图是线上真相，改线上前先改这里。
> 更新日期：2026-10-14（opencode 链路实测：防火墙 LOG + 页面 md5 + Caddyfile 取证）

## 机器

| 节点 | 公网 IP | tailnet IP | 用途 | SSH |
|---|---|---|---|---|
| mesh-hw-21（hw21） | 121.37.127.187（华北） | 100.91.222.51 | opencode-prod、litellm-guard、gh-runners | 本机直连 192.168.1.21 |
| mesh-ali-gz（120） | 120.77.76.20（阿里广州） | 100.85.128.116 | 公网入口：Caddy 终止 TLS | 只走 tailnet（22 公网关闭） |
| mesh-hw-41 | — | 100.111.231.85 | 业务（langfuse 等） | 经 hw21 |
| mesh-oci-vpn | 152.70.105.106 | 100.103.182.112 | tailnet 出口节点 | — |
| mesh-xyc-pc | — | 100.69.220.112 | 个人 PC | — |
| mesh-yx-mac | — | 100.78.144.89 | macOS（偶尔离线） | — |

tailnet 域名后缀：`*.tail137c40.ts.net`。

## 域名（Cloudflare 托管，zone：`xieyucheng.top`）

| 域名 | 类型 | 内容 | 状态 |
|---|---|---|---|
| `hw21-opencode.xieyucheng.top` | A | 120.77.76.20 | 在用：经 120 Caddy → tailnet → hw21:4097 |
| `opencode.xieyucheng.top` | CNAME | `*.w.kunlunaq.com`（华为 WAF）→ 116.117.158.55 | **死的**（2026-09-21 建后未动，后端无响应）：待改 A → 120 并上 Caddy |

## 域名（Cloudflare 托管，zone：`yingxin.net.cn`）

| 域名 | 类型 | 内容 | 状态 |
|---|---|---|---|
| `opencode.yingxin.net.cn` | A | 120.77.76.20 | 新增：mesh-ali-gz Caddy → 本机 opencode-prod-ali-gz:4097（DNS-only） |

## 入口证书

| 域名 | 签发 | 到期 | 位置 |
|---|---|---|---|
| `hw21-opencode.xieyucheng.top` | 2026-09-26（Caddy 自动） | 2026-12-25 | mesh-ali-gz |

## 链路分图

- opencode（含 browser sidecar、邮件、SSH）：`docs/opencode.md`
