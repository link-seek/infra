# litellm-gateway（网关收编栈）

目标机：`100.91.222.51`（mesh-hw-21），目录 `/root/stacks/litellm-gateway/`。
现网运行体：同机 `/root/litellm-guard`（黑户启动，`tailscale serve --tcp 4000` 对外）。

## 来源

`guard/` 三文件逐字节复制自 `link-seek/guard-rules@782c137`（md5 对齐，改动即漂移）：

| 文件 | md5 |
|---|---|
| `guard/vault_guard.py` | `bd82ab8090056deabf8cd686857434ec` |
| `guard/models-denied.json` | `0dbc7bd3462097b4f789b39ef160f2b3` |
| `guard/rules.json` | `f7c31f5191dd106f1e8727def8c6a43d` |

`config/litellm_config.yaml` 与 guard-rules 模板语义一致，唯一差异：`api_key`
改 `os.environ/GO_BACKEND_KEY` 引用（密钥只活在目标机 `.env`，同步即最终形态）。

## 本 PR 边界（PR1：只收编，不切流）

* `deploy-litellm-gateway` 合后只同步文件 + 校验（`compose config`、YAML 解析、
  与现网 `/root/litellm-guard` 的 md5 漂移报告），**不 `up`、不碰现网容器、不重启隧道**。
* 已知缺口（切流 PR 补，全部在试用窗口做）：
  1. 43 条上游模型全量：模板只带 `go-spark` + 占位格式，切流前从线上 `docker inspect` +
     线上 config 对账补齐（禁手写，由 `sync-models.py` 口径出）。
  2. `sync-models.py` 还在宿主机黑户，切流时一并收编或声明去留。
  3. ollama 数据卷是空的：切流 `up` 后另行 `ollama pull nomic-embed-text`（274MB）。
  4. 镜像 pin 与线上 `docker inspect` 对账（不一致以线上为准出 pin PR）。

## 日常（切流后生效，切流前仅供评审）

* 发版：改本目录发 PR → `test-litellm-gateway` 全绿 → 合后自动同步上机。
  `.env` 更新走 sops（workflow 永不碰 `.env`，缺失则 verify abort）。
* 黑名单增减：改 `guard/models-denied.json`（数组），保存 60 秒内生效，不用重启；
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
