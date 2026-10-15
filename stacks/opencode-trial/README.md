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
| 密钥 | sops（opencode-secrets） | sops（同体系，`envs/opencode-trial.sops.env`，1.41 为收件人） |

## 日常

* 发版：改本目录文件发 PR → `deploy-opencode-trial` 自动上机（与生产共用
  `deploy-opencode-stack`，同机制不同参数）。手动：Actions 里 dispatch。
* `.env` 更新（sops，转正后流程）：持钥机改明文 → `sops -e` 重加密 →
  secrets 仓 PR → 1.41 上 `sops -d` 落盘 600 → `compose up -d`。
  workflow 永不碰 `.env`（缺失则 verify abort）。
* 验证：`curl 127.0.0.1:4097/` → 200；`:4747` 会话激活式，无会话即掉属预期；
  Web 登录密码见 `.env`（`OPENCODE_SERVER_PASSWORD`，与生产同值，人用，另议轮换）
* 记忆验证（跑过，2026-10-14/15）：`memory add` → `api/search` 命中（similarity 0.45），跨会话以 agent 为准
* auto-capture：开（inherit 会话模型），画像 10 prompt 学一次
* 试用结束清理：`docker compose down -v` ＋ shred `.env`（sops 密文留仓，收件人可删）

## 转正清单（进生产前）

1. ~~1.41 入 sops~~ ✅ 已转正（2026-10-15：收件人＋重加密＋mem token 轮换）；
2. 机制 parity ✅（本栈与生产共用 reusable workflow，试用演练即生产演练）；
3. 待：CI 转绿 → 合 infra#12 → 灰度（老容器保留回滚）。
