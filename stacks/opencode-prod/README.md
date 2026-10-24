# opencode-prod（HW21 生产栈，记忆系统目标态）

目标机：`100.91.222.51`（mesh-hw-21），目录 `/root/stacks/opencode-prod/`。
网关依赖：宿主机 `litellm-guard`（:4000，独立栈，本目录不管；挂了生产跟挂）。

## 为什么进仓（2026-10-15 之前的状态）

生产 compose 用 `${TOOLS_IMAGE:-...:latest}` + `pull_policy: always`，而 `.env`
里根本没写 pin——每次 up 拉什么全凭 registry 当时指向谁。**无审计、无回退**。
本目录终结它：两个镜像 digest pin 死在 compose 里，版本 = git 历史。

## 发版（只手动 dispatch，合 PR 不自动发）

1. 改 `compose.yml` 里 pin（tools / chrome-cjk 二选一或都改）→ 提 PR → 合。
2. Actions 里手动点 `deliver-opencode-prod` 跑：CI 绿门（docker-images 主分支
   test-memory 必须 success，否则 fail-closed）→ tailnet 上机 → 备份线上
   compose → 下发 → pull → up → 验活（4097 通 + 运行中 digest == pin）。
3. 验活失败自动回滚：恢复备份 compose + up（旧镜像留本地，不 prune）。

回退 = revert 上次 pin 的 PR → 合 → 手动再发一次。`git log -- compose.yml`
即全部发版审计。

## 首次灰度（一次性，从旧 Alpine 迁 glibc 2.0.29）

- 线上现跑旧 Alpine（`866128bf…`，2026-10-13 起）；本 pin 是 glibc 新线
  （与 1.41 试用同一 digest，已验证 add→search 闭环）。
- 条件：CI 转绿（docker-images#3）之后。workflow 的绿门会硬拦，在此之前
  合了也只会 abort，不会动线上。
- 数据：卷名不变（`prod-work`/`prod-data`）→ L1 文件记忆保留；L2 插件是
  新增（旧镜像没有），首启空库，属预期。
- 手动兜底（workflow 万一失手）：目标机上
  `cd /root/stacks/opencode-prod && cp compose.yml.prev-<ts> compose.yml && docker compose up -d`。

## 监控注意

- `:4747` 是会话激活式的（无会话时掉，有会话回）——不要对它做裸轮询告警。
  以 agent 内 memory 调用 / 会话触发后 API 为准（试用期实证，见 docker-images#2）。
- `4097:4097` 仍绑全接口（历史状态）；收紧到回环 + tailnet 是待办，不管本次。

## 进仓红线

- `.env` 真值永不上机经 workflow（只活在目标机 + sops）；workflow 缺 `.env`
  直接 abort。
- `config/home/.{aliyun,oci}/`、`container-ssh/` 是目标机本地文件，workflow
  不下发、不删除、不覆盖。
- 卷数据（`prod-*`）workflow 永不 `down -v`。
