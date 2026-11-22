# egress 命名空间（东京 vm-proxy 出口）

本目录由 Flux（`clusters/k3s/apps-egress.yaml` → `./k8s/egress`）管理，钉在东京 **vm-proxy** 节点（`nodeSelector: kubernetes.io/hostname=vm-proxy` + 容忍 `dedicated=edge:NoSchedule`）。

## 对象

| 对象 | 作用 |
|---|---|
| `egress-proxy`（Deployment, squid） | **L7 CONNECT 出口代理**，仅放行 `opencode.ai:443`。litellm 网关通过 `HTTPS_PROXY=http://egress-proxy.egress.svc:3128` 使用它出海。`hostNetwork + privileged`，`strategy: Recreate`。 |

## 关于 xray（已移除，2026-11-22）

xray（REALITY/VLESS）曾以 host systemd 运行于 vm-proxy，并被尝试迁入 k3s；**2026-11-22 已全部停用并删除**（k3s Deployment 删除、host `xray.service` disable、`xray-config` Secret 删除）。
原因：该服务器的公网 IP（`168.110.36.240`）在**中国大陆方向 TCP 被拦**（境外 12/12 节点可连通 443，境内 ping 通但 TCP 握手不完成）——属线路/封锁问题，与 xray 版本/容器化/DNS/MTU 均无关（已逐一排除）。在本目录恢复 xray 无法解决该问题。

## 镜像门禁

镜像用**精确 digest** 且为境外源（vm-proxy 拉不到 SWR：`121.37.64.12:443` i/o timeout 实测），已在 `edge/registries/foreign-allowlist.yaml` 登记（`image-policy` 门禁）：

- `docker.io/ubuntu/squid@sha256:6a097f...`

升级镜像 = 改 digest + 同步改 foreign-allowlist 对应条目。

## 历史

- 2026-11-22：退役整套 **SNI relay**；litellm 出海改走本目录 L7 CONNECT 代理。
- 2026-11-22：xray 迁移 k3s（26.3.27 + dnsPolicy Default）后，发现公网 IP 在大陆方向 TCP 被拦；xray（host+k3s）及配置 Secret 全部移除。
