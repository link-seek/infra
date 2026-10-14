# Cloudflare DNS 说明

- 托管 zone：`xieyucheng.top`。API token 在 org secret `CLOUDFLARE_API_TOKEN`（与
  opencode-secrets 密文里的是同一把，DNS-01 与 API 共用）。
- `hw21-opencode`：A → 120.77.76.20，DNS-only（`proxied: false`），TLS 由 120 的
  Caddy 终结，不经过 Cloudflare 代理。
- `opencode`：CNAME → `opencode.xieyucheng.top.w.kunlunaq.com`（华为 WAF），
  2026-09-21 创建后未动过，解析到 116.117.158.55，80 端口无响应——**死记录**，
  新域名上线时删除并改 A → 120.77.76.20。
- 查记录（token 不出远端，脚本在目标机上跑，见 2026-10-14 操作记录）。


> 真相源：dns/records.json（dns-apply.yml 自动对账）。本文件只记背景：WAF 死 CNAME（9/21 建）阶段一删除，见 records.json bsent 条。