# opencode-trial（1.41 试用栈，记忆系统验证）

目标机：`100.111.231.85`（mesh-hw-41，8c/31G），目录 `/root/stacks/opencode-trial/`。

## 与生产差异（有意为之）

| 项 | 生产 HW21 | 试用 1.41 |
|---|---|---|
| 镜像 | Alpine 旧版（stable） | glibc 新版（digest pin，见 compose） |
| 数据卷 | prod-* | trial-*（独立，L1 已播种 GLOBAL） |
| 网关 | 宿主机 4000（host 内部） | tailscale 直连 HW21 `100.91.222.51:4000` |
| browser sidecar | 有 | 无（记忆试用不需要） |
| 云凭证/邮件/SSH | 全 | 无（工具在，认证不在——试用不测云） |
| 密钥 | sops（opencode-secrets） | **例外：手工 .env（600），试用结束 shred** |

## 日常

* 启动/更新：`cd /root/stacks/opencode-trial && docker compose up -d`（镜像 digest pin，只会拉到验证过的版本）
* 验证：`curl 127.0.0.1:4097/` → 200；`:4747/api/health` → ok（插件）；Web 登录密码见 `.env`
* 记忆验证（跑过，2026-10-14）：`memory add` → `api/search` 命中（similarity 0.45），跨会话以 agent 为准
* auto-capture：开（inherit 会话模型），画像 10 prompt 学一次
* 试用结束清理：`docker compose down -v` ＋ `shred -u .env`（密钥随试用终结）

## 转正清单（进生产前）

1. 1.41 入 sops 收件人＋全量重加密＋值轮换（持钥人操作）；
2. 本目录 compose/config 原样搬 infra 正式栈（或就地转正改名）；
3. infra 灰度流程（影子→切流，老容器保留回滚）。
