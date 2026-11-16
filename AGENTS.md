# 协作分工（2026-11-16：机器人写码，人只审合）

- 写码优先走仓库机器人（coding agent 出 PR）；OpenCode 默认只做合码前审阅，不直接动手改。
- 人只负责审 PR + 点 merge；机器人 PR 必须写清影响面与回滚法。
- 例外：机器人搞不定、线上救火，人点名 OpenCode 才动手。

# 本仓定位

infra 只留底座：flux-system、egress、etcd、Caddy/DNS、tailnet、namespace/配额/网络策略。pod 层一律是应用仓的事，本仓不伸手（与 infra#461 同源）。
