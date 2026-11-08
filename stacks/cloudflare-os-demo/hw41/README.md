# cloudflare-os-demo（HW41 试用）

cloudflare-os（`link-seek/cloudflare-os` pin 版）run-local 落 HW41 的 demo 栈。
背景：免费号发不到 CF 线上（Dynamic Workers 要 Paid），先在 HW41 验证全功能试用。

* 入口：`http://100.111.231.85:18787`（tailnet，手机/电脑挂 tailnet 访问）
* 状态卷 `wrangler-state`：重建不丢会话
* 密钥：`CLOUDFLARE_API_TOKEN`（远端 AI/R2 binding），deliver 现场 render，不进仓
* 无 SLA；上游 early-access，升级=换 gitlink 发 PR
* 转正（Paid 开通后）：发 CF 线上，本栈退役
