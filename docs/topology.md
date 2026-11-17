# link-seek 基础设施总图

> 唯一源声明：本文件与各分图是线上真相，改线上前先改这里。
> 更新日期：2026-11-16（HW21重建成第3 server + 三机/data全挂 + 内网mesh免密打通，report 43891127961 / deploy 43896654528 取证）

## 机器（k3s 3 server，全对齐）

| 节点 | LAN / tailnet IP | 系统/版本 | 盘/挂载 | SSH |
|---|---|---|---|---|
| mesh-hw-21（hw21） | 192.168.1.21 / 100.100.246.95 | EulerOS 2.0 / k3s v1.37.2+k3s1 / cgroup v2 | vda 150G（/ 3.2G）· vdb 150G ext4 → /data 147G空盘 | tailnet user + CI key＋密码（PROD_SSH_PASSWORD，server-password 链维护）；EIP 121.37.127.187占位待解绑 |
| mesh-hw-41 | 192.168.1.41 / 100.73.182.4 | EulerOS 2.0 / k3s v1.37.2+k3s1 / cgroup v2 | vda 150G（/ 31G）· vdb 150G vdb1 147G → /data 9.2G已有数据 | tailnet user + CI key＋密码（PROD_SSH_PASSWORD，server-password 链维护） |
| mesh-hw-69 | 192.168.1.69 / 100.93.119.21 | EulerOS 2.0 / k3s v1.37.2+k3s1 / cgroup v2 | vda 150G（/ 44G）· vdb 150G ext4 → /data 147G空盘已挂 | tailnet user + CI key＋密码（PROD_SSH_PASSWORD，server-password 链维护） |
| mesh-ali-gz（120） | 120.77.76.20 / 100.85.128.116 | 公网入口：Caddy 终止 TLS | — | 只走 tailnet（22 公网关闭） |
| mesh-oci-vpn | 152.70.105.106 / 100.103.182.112 | tailnet 出口节点 | — | — |
| mesh-xyc-pc | — / 100.69.220.112 | 个人 PC | — | — |
| mesh-yx-mac | — / 100.78.144.89 | macOS（偶尔离线） | — | — |

内网mesh免密：每机独立mesh_id（私钥不出机），公钥互换，9向BatchMode全通（deploy 43896654528）。tailnet 域名后缀：`*.tail137c40.ts.net`。

备份：k3s每6h打etcd快照直传OBS华北9桶（CronJob + 临时密钥刷S3配置）；每天01:00只verify（30h内有新鲜快照 + Secret 12h刷过），不动集群。恢复点在桶里，跟机器死活解耦。

## 域名（Cloudflare 托管，zone：`xieyucheng.top`）

| 域名 | 类型 | 内容 | 状态 |
|---|---|---|---|
| `hw21-opencode.xieyucheng.top` | A | 120.77.76.20 | 在用：经 120 Caddy → tailnet → hw21:4097 |
| `opencode.xieyucheng.top` | CNAME | `*.w.kunlunaq.com`（华为 WAF）→ 116.117.158.55 | **死的**（2026-09-21 建后未动，后端无响应）：待改 A → 120 并上 Caddy |

## 域名（Cloudflare 托管，zone：`yingxin.net.cn`）

| 域名 | 类型 | 内容 | 状态 |
|---|---|---|---|
| `opencode.yingxin.net.cn` | A | 120.77.76.20 | 新增：mesh-ali-gz Caddy → tailnet → hw41:4097（容器在 hw41，DNS-only） |

## 入口证书

| 域名 | 签发 | 到期 | 位置 |
|---|---|---|---|
| `hw21-opencode.xieyucheng.top` | 2026-09-26（Caddy 自动） | 2026-12-25 | mesh-ali-gz |

## 链路分图

- opencode（含 browser sidecar、邮件、SSH）：`docs/opencode.md`
