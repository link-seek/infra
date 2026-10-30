# litellm-gateway（网关收编栈）

目标机：`100.91.222.51`（mesh-hw-21），目录 `/root/stacks/litellm-gateway/`。
现网运行体：同机 compose 栈 `/root/stacks/litellm-guard/`（`restart-guard.sh` 重建入口）＋
文件 `/root/litellm-guard/`（`tailscale serve --tcp 4000` 对外）；隧道 `hw21-opencode`
（`/etc/cloudflared/config.yml`：`hw21-opencode`→4097、`opendesign`→7456）。

## 对账（2026-10-15，取证 run 38730436491 / 38731186781，密钥全打码）

| 项 | 结论 |
|---|---|
| 网关镜像 | ✅ 一致（`ghcr.io/berriai/litellm@3def0387`，线上 `inspect` 同 digest） |
| 挂载 | ✅ 同构（4 个 `:ro`） |
| 模型表 | ✅ 45 条全量已收（线上 46 行含 1 条注释掉的 `go-spark-b`，未收；`space-bunny-free` 上游已死，原样保留，删不删切流定） |
| `vault_guard.py` | ⚠️ 仓新（27965B）线旧（27296B，9-28），切流=升级；线上 hotfix 有无必须 diff（持钥人本地做，不进 CI 日志） |
| `guard-rules.json` | ⚠️ 内容不一（线上 1136B vs 仓 `rules.json` 1652B；线上另配 `RULES_URL` 走 R2），切流对账 |
| DNS | ⚠️ `opendesign.xieyucheng.top` 在隧道里但不在 `dns/records.yaml`（漂移，另起） |

## 来源

`guard/` 三文件逐字节复制自 `link-seek/guard-rules@782c137`（md5 对齐，改动即漂移）：

| 文件 | md5 |
|---|---|
| `guard/vault_guard.py` | `bd82ab8090056deabf8cd686857434ec` |
| `guard/models-denied.json` | `0dbc7bd3462097b4f789b39ef160f2b3` |
| `guard/rules.json` | `f7c31f5191dd106f1e8727def8c6a43d` |

`config/litellm_config.yaml` 与 guard-rules 模板语义一致，唯一差异：`api_key`
改 `os.environ/GO_BACKEND_KEY` 引用（密钥只活在目标机 `.env`，同步即最终形态）。

## 部署

* `deliver-litellm-gateway`：只手动 dispatch（Actions 里点火，digest 默认 stable）。共用 `scripts/canary-*.sh`
  起 canary、跑 goss runner（本栈只在 `deploy.manifest` 留参数）：
  `goss-gateway.yaml` 断言就绪（容器 IP:4000）、镜像 pin、黑名单 400；真/假 key verdict 透传（要解析 JSON 回包）
  留在 `probe-cases/verdict-passthrough.sh`。junit 与统一表落靶机 `.probe-results/`；任一红即丢 canary，旧容器全程在线，
  绿才 `force-recreate` 正式容器（trial/prod 统一全跑 full）。手动发一次即跑全套。
  goss 二进制版本由 `deploy.manifest` 的 `GOSS_VERSION` 钉死，复用线下载后与栈文件同路送上靶机。
* 镜像构建 + 行为门在 `link-seek/docker-images` 仓 `bake-gateway.yml`（测试归镜像构建）。
  `.env` 更新走 render-dotenv（workflow 永不手写 `.env`）。
* 黑名单增减：改 `guard/models-denied.json`（数组）后必须走 bake 重打才生效
  （guard 烘进镜像，infra 这份只是 bake 的来源；bake 构建时从 main 拉取）。
  流程：改本文件合 PR → 手动 dispatch `bake-gateway`（docker 仓）→ promote 打 tag（reason 必填，审计进 run 日志）→ 手动 dispatch `deliver-litellm-gateway`。直接合本仓只会触发一次空跑部署，新名单不会生效。
  空数组 = 全放行；文件坏掉 = 全拦（fail-closed）。
* 验证（现网 4000，master key 见 sops）：
```bash
curl -s http://100.91.222.51:4000/v1/models -H "Authorization: Bearer $LITELLM_MASTER_KEY" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['data']))"
curl -s http://100.91.222.51:4000/v1/chat/completions -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" -d '{"model":"glm-5.2","messages":[{"role":"user","content":"reply with exactly: LITELLM-OK"}]}'
# 黑名单（应 400 ModelBlocked）：
curl -s http://100.91.222.51:4000/v1/chat/completions -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" -d '{"model":"kimi-k3","messages":[{"role":"user","content":"hi"}]}'
```
* `:4747` 式误报注意：本网关无会话激活行为，4000 常驻；监控直接轮询 `/v1/models` 即可。

## HTTPS（PR2，另起）

* 试用域名 `llm-trial.xieyucheng.top` 先行，正式 `llm.xieyucheng.top` 等试用全绿；
  动隧道前先看本文“现网运行体”，回滚 = OD 切回 `http://100.91.222.51:4000`。
