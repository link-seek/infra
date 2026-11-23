# ts/ — Tailscale 声明式配置真相源（一期）

`acl/policy.hujson`（ACL）早已是声明式；本目录补上剩下两块，
终态：所有 ts 配置进仓，workflow 只做 verify/apply（同 `node/node-config.yaml` 模式）。

## 文件

| 文件 | 说明 |
|---|---|
| `daemon.ci.json.tmpl` | CI 临时机 daemon 模板（alpha0 最小子集），`__TS_AUTHKEY__`/`__TS_HOSTNAME__` 运行时填 |
| `devices.yaml` | 设备期望状态：CI 约定 + 4 台常驻机（tags 待首轮 verify 回填，`verified:false`） |
| `render.py` | 纯逻辑：`render` 渲染模板 / `check-devices` 核对控制台与期望 |

## 纪律

- authKey 永不进仓：`render` 只从 env `TS_AUTH_KEY` 取（`ts-mint` 现签），文件 `600`，用后 shred。
- CI 用 `locked:false`（`logout`/重进不卡死）；常驻机切声明式时用 `locked:true`（二期）。
- 字段冻结在 7 个：`version/authKey/hostname/locked/enabled/acceptDNS/acceptRoutes`，
  serve/relay/VIP 不用，等官方转正。
- `verified:false` 条目 reconcile 只告警不强改（fail-closed），首轮 verify 确认 tags 后再翻 true。

## 路线图

- 一期（本 PR）：只加文件，零行为变更；现有 20 处 `tailscale up` 不动。
- 二期：`runner-net` 加 `conffile` 模式 + `edge-probe` 试点，回退即切回 `up` 一行。
- 三期：`devices.yaml` 接 reconcile（verify/apply/tag-device/approve-routes），常驻机 daemon 进仓（低峰 + 手动 dispatch）。

## 回滚

删 `ts/` 即回退，本 PR 不碰任何 workflow，不删回滚逻辑。
