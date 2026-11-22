# egress 命名空间（东京 vm-proxy 出口）

本目录由 Flux（`clusters/k3s/apps-egress.yaml` → `./k8s/egress`）管理。全部钉在东京 **vm-proxy** 节点（`nodeSelector: kubernetes.io/hostname=vm-proxy` + 容忍 `dedicated=edge:NoSchedule`），提供东京出口能力。

## 对象

| 对象 | 作用 |
|---|---|
| `egress-proxy`（Deployment, squid） | **L7 CONNECT 出口代理**，仅放行 `opencode.ai:443`。litellm 网关通过环境变量 `HTTPS_PROXY=http://egress-proxy.egress.svc:3128` 使用它出海（含"按来源地区放行"的模型）。 |
| `xray`（Deployment, xtls/xray-core） | **REALITY/VLESS 多出口代理**（inbounds 443/8443/9443/10443，outbounds `sendThrough` 不同源 IP），2026-11-22 从 vm-proxy 主机 systemd 迁入。 |

两者都 `hostNetwork: true` + `privileged: true`，且 `strategy: Recreate`（hostNetwork 单副本绑定节点端口，滚动会撞端口）。

## ⚠️ xray-config Secret（不入 git，需人工重建）

xray 的配置 **含 UUID / REALITY 私钥**，**不进仓库**；`xray` Deployment 挂载集群内 Secret `egress/xray-config`（key = `config.json`），同 `litellm-env` 的"不进仓、直接建"模式。

- **备份位置**：vm-proxy 主机 `/usr/local/etc/xray/config.json`（迁移时未删除，保留作备份）。
- **集群重建 / Secret 丢失时重建命令**（在能访问该备份的机器上，或先从 vm-proxy 取回）：

```bash
# 1) 取得配置备份（示例：从 vm-proxy 主机）
ssh root@<vm-proxy> 'cat /usr/local/etc/xray/config.json' > xray-config.json

# 2) 建/更新集群 Secret（不落 git）
kubectl -n egress create secret generic xray-config \
  --from-file=config.json=xray-config.json \
  --dry-run=client -o yaml | kubectl apply -f -

# 3) 重启 xray pod 使生效
kubectl -n egress rollout restart deploy/xray

# 4) 校验（应可解析、inbounds 含 443/8443/9443/10443）
kubectl -n egress get secret xray-config -o jsonpath='{.data.config\.json}' | base64 -d | python3 -m json.tool >/dev/null && echo OK
```

> 换机/重建集群务必先备份上述 `xray-config.json` 到安全位置（它不在任何仓库里）。

## 镜像 / 门禁

- 镜像均为**精确 digest**，且是境外源（SWR 到 vm-proxy 不通：`121.37.64.12:443` i/o timeout 实测），已在 `edge/registries/foreign-allowlist.yaml` 逐条登记（`image-policy` 门禁）：
  - `docker.io/ubuntu/squid@sha256:6a097f...`
  - `ghcr.io/xtls/xray-core@sha256:9812e382...`
- 升级镜像 = 改 digest + 同步改 foreign-allowlist 对应条目。

## 历史

- 2026-11-22：退役整套 **SNI relay**（原 `daemonset*.yaml`/`nginx-conf.yaml` + egress 工作流）；litellm 出海改走本目录的 L7 CONNECT 代理。
- 2026-11-22：**xray 从 vm-proxy host systemd 迁入 k3s**（本目录），host 的 `xray.service`、`tinyproxy.service` 停用；vm-proxy 主机业务只剩 `k3s-agent` + `tailscaled`。
