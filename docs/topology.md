# link-seek 基础设施总图

> 唯一源声明：本文件与各分图是线上真相，改线上前先改这里。
> 更新日期：2026-11-22（Traefik 接管 80/443、宿主 Caddy 退役；xray 退出 k3s 且主机退役；flannel 走 TS underlay 见 2026-11-21 段）

## 机器（k3s 3 server，全对齐）

| 节点 | LAN / tailnet IP | 系统/版本 | 盘/挂载 | SSH |
|---|---|---|---|---|
| mesh-hw-21（hw21） | 192.168.1.21 / 100.100.246.95 | EulerOS 2.0 / k3s v1.37.2+k3s1 / cgroup v2 | vda 150G（/ 3.2G）· vdb 150G ext4 → /data 147G空盘 | tailnet user + CI key＋密码（PROD_OPENCODE_SERVER_PASSWORD，server-password 链维护）；EIP 121.37.127.187占位待解绑 |
| mesh-hw-41 | 192.168.1.41 / 100.73.182.4 | EulerOS 2.0 / k3s v1.37.2+k3s1 / cgroup v2 | vda 150G（/ 31G）· vdb 150G vdb1 147G → /data 9.2G已有数据 | tailnet user + CI key＋密码（PROD_OPENCODE_SERVER_PASSWORD，server-password 链维护） |
| mesh-hw-69 | 192.168.1.69 / 100.93.119.21 | EulerOS 2.0 / k3s v1.37.2+k3s1 / cgroup v2 | vda 150G（/ 44G）· vdb 150G ext4 → /data 147G空盘已挂 | tailnet user + CI key＋密码（PROD_OPENCODE_SERVER_PASSWORD，server-password 链维护） |
| mesh-ali-gz（120） | 120.77.76.20 / 100.85.128.116 | 公网入口：Traefik(k3s, hostNetwork) 接管 80/443（宿主 Caddy 已退役） | — | 只走 tailnet（22 公网关闭） |
| mesh-oci-vpn | 152.70.105.106 / 100.103.182.112 | tailnet 出口节点 | — | — |
| mesh-xyc-pc | — / 100.69.220.112 | 个人 PC | — | — |
| mesh-yx-mac | — / 100.78.144.89 | macOS（偶尔离线） | — | — |

内网mesh免密：每机独立mesh_id（私钥不出机），公钥互换，9向BatchMode全通（deploy 43896654528）。tailnet 域名后缀：`*.tail137c40.ts.net`。

备份：k3s每6h打etcd快照直传OBS华北9桶（CronJob + 临时密钥刷S3配置）；每天01:00只verify（30h内有新鲜快照 + Secret 12h刷过），不动集群。恢复点在桶里，跟机器死活解耦。

## k3s 网络（2026-11-21：flannel 走 TS underlay）

- **datapath**：所有 k3s 节点 `flannel-iface=tailscale0`，VXLAN over tailnet，`flannel.1 MTU=1230`（tailscale 1280 − 50）。
- **server 寻址**：HW 三台 `node-ip=<LAN 192.168.1.x>`（etcd/API 确定性）+ `node-external-ip=<该机 tailnet IP>`（令 flannel `public-ip = VTEP`，跨云可通）；edge（ali/oci）node-ip 即 tailnet IP。
- **声明式**：`k3s/node-config.yaml` 为节点配置真相；`.github/workflows/k3s-node-config.yml`（verify 每日巡检 / apply 写入）。
- **验证（2026-11-21）**：5 节点 flannel.1 均 `local=<tailnet> dev tailscale0 mtu1230`、public-ip=tailnet；跨节点 pod 3×3 全 200；业务域名 200。存量 pod MTU 1450 待滚动重建收敛到 1230。

## 域名（Cloudflare 托管，zone：`xieyucheng.top`）

| 域名 | 类型 | 内容 | 状态 |
|---|---|---|---|
| `hw21-opencode.xieyucheng.top` | A | 120.77.76.20 | 已下线（2026-11-02 退役，Caddy vhost 删） |
| `opencode.xieyucheng.top` | A | 120.77.76.20 | 在用：Traefik(mesh-ali-gz, k3s hostNetwork, websecure) → opencode pod（IngressRoute xieyucheng-staging-tls） |

## 域名（Cloudflare 托管，zone：`yingxin.net.cn`）

| 域名 | 类型 | 内容 | 状态 |
|---|---|---|---|
| `opencode.yingxin.net.cn` | A | 120.77.76.20 | 在用：Traefik(mesh-ali-gz, k3s hostNetwork, websecure) → opencode-yingxin pod（IngressRoute yingxin-staging-tls） |

## 入口证书

| 入口 | 说明 |
|---|---|
| opencode.xieyucheng.top / opencode.yingxin.net.cn | 现由 k3s Traefik(websecure) 按 IngressRoute 挂 TLS secret（`xieyucheng-staging-tls` / `yingxin-staging-tls`）；Caddy 自动证书随入口退役 |

## 链路分图

- opencode（含 browser sidecar、邮件、SSH）：`docs/opencode.md`（注：该分图仍是旧 docker-compose 时代，待按 k3s 现状重写）
