# OpenCode Ops —— K3S 维护台（HW21 宿主机，Route A）

> 单机容器化 OpenCode 维护台，**独立于 K3S 故障域**（K3S 挂了它仍在），用于救火/日常运维。
> 组件：docker-ce（华为镜像站，cgroup v2）+ docker compose v2 + systemd。理由见下方"选型"。

## 目录
```
ops/opencode-ops/
├── compose.yaml            # 应用真相（镜像 tag 单点 pin 在 VERSION）
├── ensure-docker.sh        # 幂等装 docker-ce（华为镜像站 el8 源）+ daemon.json 与 k3s 共存
├── opencode-ops.service    # systemd 包 `docker compose up -d`
├── env.example             # /etc/opencode-ops/.env 样例（真实值由流水线从组织 secrets 渲染）
└── VERSION                 # 镜像 tag 单点（升级=改这里→合 PR→流水线）
.github/workflows/opencode-ops-deploy.yml   # push ops/** 或手动 dispatch 下发
```

## 首次部署（先跑通 opencode-tools，再切 opencode-ops）
1. 合并 PR 后，Actions → `opencode-ops-deploy` → Run workflow：
   - 首次可填 `app_repo=opencode-tools`、`app_tag=<现有 tag 或 sha256 digest>` 先行跑通；
   - 之后镜像线 `bake-ops` 产出 `opencode-ops:<tag>`，把 `VERSION` 改掉即自动切。
2. 部署完成：`systemctl status opencode-ops`、`docker compose -f /opt/opencode-ops/compose.yaml ps`。
3. 访问：tailnet 内 `https://mesh-hw-21-1.<tailnet>/`（`tailscale serve`）+ `OPENCODE_SERVER_PASSWORD`。

## 日常/升级
- `/workspace` 首次启动自动 `git init`（容器 `WorkingDir=/workspace`），OpenCode 的 worktree 功能依赖此 git 仓库。
- 升级镜像：改 `ops/opencode-ops/VERSION` → 合 PR → 流水线 `compose pull && up -d`。
- 手动重建：`systemctl restart opencode-ops`。
- 回滚：`VERSION` 改回旧 tag 合 PR。

## 选型说明（为什么不是 podman-quadlet）
- 社区最佳实践严格说是 **Podman + Quadlet**（daemonless/rootless、systemd 原生、`podman auto-update`）。
- 但 HW21 是 **HCE 2.0（glibc 2.34，openEuler 22.03 血统）**，**没有可用新 podman 包**（openEuler `everything` 源 repodata 只解析到 0.10.1），而 **docker-ce 从华为镜像站可干净安装**（26.x，支持 cgroup v2，仅依赖 HCE 自带 container-selinux/libcgroup）。
- 故本机走 docker-ce，并按最佳实践姿势组织：compose 为真相 + digest/tag pin + systemd `Type=oneshot/RemainAfterExit` 守护 + healthcheck + `--remove-orphans`。
- 若日后要正统 podman-quadlet：把本维护台迁到 openEuler/Ubuntu 小 ECS，用 `.container` + `AutoUpdate=registry` + `podman-auto-update.timer`。

## 公网入口（2026-11-27 上线）
- `https://opencode-ops.xieyucheng.top` → Cloudflare A `120.77.76.20`（Aliyun edge，proxied=false）→ Traefik(edge) → tailnet `100.100.246.95:4097`。
- TLS：Traefik `certResolver: le-prod`（Let's Encrypt DNS-01，Cloudflare）。
- 认证：**单层**——应用层 `OPENCODE_SERVER_PASSWORD`（BasicAuth，用户名 `opencode`；与 opencode/home-oc 一致，不在 Traefik 叠口令）。
- 路由清单：`k8s/traefik-edge/opencode-ops.yaml`；DNS：`iac/terraform/cloudflare/dns.tf`（含 import 块，首次 apply 后删除）。
- 可选更强门禁：**Cloudflare Access**（DNS 改 proxied=true + Zero Trust 策略），替代口令层。

## 安全
- 公网仅暴露 443（经 edge），HW21 无入站端口；容器只绑 tailnet IP。
- 单层应用口令 `OPENCODE_SERVER_PASSWORD`。
- kubeconfig 只读挂宿主 k3s.yaml；SSH 复用宿主 mesh_id；云 AK/密钥走组织 secrets 注入，不进仓库、不进镜像。
- kubeconfig 为 admin：本机即"救火台"，务必限制登录。
