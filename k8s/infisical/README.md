# infisical 命名空间（自建密钥管理，替代 SOPS 密文进仓）

本目录由 Flux（`clusters/k3s/apps-infisical.yaml` → `./k8s/infisical`）管理。部署在 **hw21（ecs-…-xieyucheng）**，数据放本地 `/data/infisical`（PG/Redis 不放 NFS）。

## 组件
| 对象 | 说明 |
|---|---|
| `infisical-postgres` | PostgreSQL 14（存所有加密后的 secret，`/data/infisical/pg`） |
| `infisical-redis` | Redis 7（AOF + `noeviction`，队列/锁，`/data/infisical/redis`） |
| `infisical` | Infisical server（:8080） |
| `infisical-pg-backup` | 每日 03:00 `pg_dump` → `/data/infisical/backups`（保留 14 天） |
| Infisical Operator（`k8s/infisical-operator`） | 把 Infisical 里的值按 `InfisicalSecret` CR 同步成 k8s Secret |

## ⚠️ 必读：根密钥（不进 git）
- **`infisical-env`** Secret（集群内一次性建，含 `ENCRYPTION_KEY` / `AUTH_SECRET` / `DB_CONNECTION_URI` / `POSTGRES_*` / `REDIS_URL` / `SITE_URL`）——**不在仓库**。
- **`ENCRYPTION_KEY` 必须离线另存**：没有它，即使有 PG 备份也解不开任何密钥（官方明确）。丢了=全部密钥报废。
- admin 账号密码存 `infisical-bootstrap`，实例管理员 token 存 `infisical-admin`（供自动化）。

## 备份 / 恢复（官方方法：pg_dump + 保护 ENCRYPTION_KEY）
- 自动：`infisical-pg-backup` 每日 dump 到 `/data/infisical/backups/infisical-<ts>.dump`（`pg_dump -Fc`），保留 14 天。
- **离线异机**：将 `/data/infisical/backups` 同步到 OBS（复用现有 etcd→OBS 的 24h 临时钥匙/桶；建议纳入同一备份桶）。
- 恢复：
  ```bash
  # 1) 用同一 ENCRYPTION_KEY 重建 infisical-env（否则解不开）
  # 2) 恢复 PG（先停 infisical server）
  kubectl -n infisical scale deploy/infisical --replicas=0
  kubectl -n infisical exec -i deploy/infisical-postgres -- \
    pg_restore -U infisical -d infisical --clean --if-exists < infisical-<ts>.dump
  kubectl -n infisical scale deploy/infisical --replicas=1
  ```

## 集群重建 / 根密钥 bootstrap
1. 生成根 Secret（`ENCRYPTION_KEY=$(openssl rand -hex 16)`、`AUTH_SECRET=$(openssl rand -base64 32)`、DB 口令），`kubectl -n infisical create secret generic infisical-env ...`（不入库）。
2. 等 pod 起来：`curl http://<pod-ip>:8080/api/status` 应 200。
3. Bootstrap 管理员/组织/实例管理员 token：`POST /api/v1/admin/bootstrap {email,password,organization}`（token 存 `infisical-admin`）。
4. 每个应用：在本仓 `iac/infisical/apps.json` 加一行声明 → 跑 `.github/workflows/infisical-provision.yml`（默认 dry-run，`apply=true` 才变更）自动确保「项目 / 机器身份 `<slug>-operator` / 项目授权 / `<ns>-ua` secret」存在（只补缺、不动已有）；密钥值仍在 Infisical 里灌；建 `InfisicalSecret` CR（见 `k8s/infisical-apps/`）。

## 镜像
`infisical` / `postgres:14-alpine` / `redis:7-alpine` / `kubernetes-operator:v0.11.18` 均从 SWR（`swr.cn-north-9.../link-seek/...`）拉取；因华为节点直连 docker.io 不通，镜像由 docker-images 仓的 `images/mirror.yaml`（runner 侧 skopeo 同步）mirror 进 SWR。
