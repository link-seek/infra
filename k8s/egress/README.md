# egress 命名空间（东京 vm-proxy 出口）

本目录由 Flux（`clusters/k3s/apps-egress.yaml` → `./k8s/egress`）管理，全部钉在东京 **vm-proxy** 节点（`nodeSelector: kubernetes.io/hostname=vm-proxy` + 容忍 `dedicated=edge:NoSchedule`），提供东京出口能力。

## 对象

| 对象 | 作用 |
|---|---|
| `egress-proxy`（Deployment, squid） | **L7 CONNECT 出口代理**，仅放行 `opencode.ai:443`。litellm 网关通过 `HTTPS_PROXY=http://egress-proxy.egress.svc:3128` 使用它出海。 |
| `xray`（Deployment, xtls/xray-core **26.3.27**） | **REALITY/VLESS 多出口代理**（手机及多设备直连 `vm-proxy:443`，inbounds 443/8443/9443/10443）。2026-11-22 从 vm-proxy 主机 systemd **迁入 k3s**。 |

两者都 `hostNetwork: true` + `privileged: true`，且 `strategy: Recreate`（hostNetwork 单副本绑定节点端口，滚动会撞端口）。

## ⚠️ xray 容器的两个致命坑（务必保留）

1. **镜像版本必须锁定 `26.3.27`（= 主机现网原版）**。
   - 曾用 `ghcr.io/xtls/xray-core:latest`（26.11.9）迁入 → REALITY 握手失败，手机报 `TLS handshake timeout`。
   - 升级版本前**必须在 vm-proxy 本机做回环握手实测通过**再切流量。
2. **`dnsPolicy` 必须是 `Default`**（= 节点自身 resolv.conf / systemd-resolved）。
   - 用 `ClusterFirstWithHostNet` 会走集群 DNS，实测把部分域名（如 `www.gstatic.com`）解析成**错误/污染 IP（北京 114.250.x）**，导致隧道握手成功后**出口 dial 死连、卡超时**。
   - 现象：客户端已 `tunneling request`、服务端已 `received request`，但 `proxy/freedom: dialing ...` 后无 `connection opened`。
3. 启动要加载 geoip/geosite（约 15s）后才监听端口，就绪探针已放宽（`failureThreshold: 12`）。

## ✅ 迁移/改动后的验收方法（必做，勿只看 pod Running）

在 **vm-proxy 本机**用同版本 `xray` 当客户端，做**真实握手 + 走隧道取 204** 的回环测试（这是唯一能发现版本/DNS/出口问题的办法）：

```bash
# 目标：127.0.0.1:<端口>，从主机 config 取 UUID/私钥/shortId/serverName 生成客户端
# 期望：curl 经 socks 取回 HTTP 204
curl -s -o /dev/null -w '%{http_code}\n' --max-time 15 \
  --socks5-hostname 127.0.0.1:<本地socks端口> https://www.gstatic.com/generate_204   # 期望 204
```

> 注意：从境内/公网直连 `168.110.36.240:443` 会被墙（timeout），所以验收在 vm-proxy 本机回环做。
> 首次迁移时正确做法：先用旁路端口（如 14443）测通，再停 host xray 切 443，切后**对 443 再测一次**。

## ⚠️ xray-config Secret（不入 git，需人工重建）

xray 配置 **含 UUID / REALITY 私钥**，**不进仓库**；`xray` Deployment 挂载集群内 Secret `egress/xray-config`（key=`config.json`），同 `litellm-env` 的"不进仓、直接建"模式。

- **备份位置**：vm-proxy 主机 `/usr/local/etc/xray/config.json`（迁移时未删除，保留作备份）。
- **集群重建 / Secret 丢失时重建**：

```bash
# 1) 取得配置备份（示例：从 vm-proxy 主机）
ssh root@<vm-proxy> 'cat /usr/local/etc/xray/config.json' > xray-config.json

# 2) 建/更新集群 Secret（不落 git；在能 kubectl 控制集群的机器上）
kubectl -n egress create secret generic xray-config \
  --from-file=config.json=xray-config.json \
  --dry-run=client -o yaml | kubectl apply -f -

# 3) 重启 xray pod 使生效
kubectl -n egress rollout restart deploy/xray

# 4) 校验（应可解析、inbounds 含 443/8443/9443/10443）
kubectl -n egress get secret xray-config -o jsonpath='{.data.config\.json}' | base64 -d | python3 -m json.tool >/dev/null && echo OK
```

> 换机/重建集群务必先备份上述 `xray-config.json` 到安全位置（它不在任何仓库里）。

## 镜像门禁

镜像均为**精确 digest** 且是境外源（vm-proxy 拉不到 SWR：`121.37.64.12:443` i/o timeout 实测），已在 `edge/registries/foreign-allowlist.yaml` 逐条登记（`image-policy` 门禁）：

- `docker.io/ubuntu/squid@sha256:6a097f...`
- `ghcr.io/xtls/xray-core@sha256:592ec4d1...`（26.3.27）

升级镜像 = 改 digest + 同步改 foreign-allowlist 对应条目。

## 历史

- 2026-11-22：退役整套 **SNI relay**（原 `daemonset*.yaml`/`nginx-conf.yaml` + egress 工作流）；litellm 出海改走本目录 L7 CONNECT 代理。
- 2026-11-22：xray 首次尝试迁入 k3s（latest 26.11.9）→ 未做端到端测试即切换 → REALITY 握手失败、手机断网 → **回滚**到 host systemd。
- 2026-11-22：定位根因（版本不一致 + `ClusterFirstWithHostNet` 错误 DNS），改用 **26.3.27 + `dnsPolicy: Default`**，**先旁路端口回环实测 PASS** 后再切 443，迁移成功；host `xray.service`/`tinyproxy.service` 停用，vm-proxy 主机业务只剩 `k3s-agent` + `tailscaled`。
