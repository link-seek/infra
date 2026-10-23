# opendesign（OD 收编栈）

目标机：`100.91.222.51`（mesh-hw-21），切流后目录 `/root/stacks/opendesign/`。
现网运行体：同机 `/root/opendesign/compose.yml`（黑户启动，tunnel → `127.0.0.1:7456`）。

## 对账（2026-10-16，SSH 只读取证，密钥全打码）

| 项 | 现网 | 本栈 | 结论 |
|---|---|---|---|
| 镜像 | `swr…/opendesign:0.24.1-oc2.0.6`（image ID `36f61417`） | 同 tag 的 manifest digest `d5688efe…` pin | ✅ 同一构建，pin 死 |
| 端口 | 仅 `127.0.0.1:7456` | 同 | ✅ 一致（隧道打 127.0.0.1，无需网桥绑定） |
| 数据 | 具名卷 `opendesign_od-data`＋`/root/opendesign/home` 绝对路径 | `name:` 显式复用卷；home 不搬家 | ✅ 数据不动 |
| 密钥 | `OD_API_TOKEN` 等**明文写在 compose 里**＋`.env` 2 个 | 全改 `${VAR}` 引用＋`env_file`，`.env` 走 sops | ⚠️ 切流前必须先落盘 `.env`（缺失则 deploy abort） |
| 更新 | `watchtower.enable=true`（每周六 20:00 自动拉 tag 重启） | label 已摘，改 pin PR＋deploy | ⚠️ 切流即关闭自动更新（与全仓 pin 策略对齐） |
| 网关指向 | `LITELLM_BASE_URL=http://100.91.222.51:4000`（tailnet 内网 HTTP） | 同（`.env.example` 占位） | ✅ 服务端不受 `llm` HTTPS 切换影响 |

## 本 PR 边界（只收编，不切流）

* `deliver-opendesign.yml` 为 `workflow_dispatch` 专属（**无 push 触发**）：合 PR 只同步校验，不上机、不 `up`、不动现网容器。
* 切流（另约窗口，`confirm=CUTOVER` 才执行）：备份旧目录 → 同步文件 → `.env` 存在性门禁 → `up -d` → verify（见下）→ 失败回滚旧目录 `up`。
* deploy 永不 `down -v`（卷里是 OD 全量数据）。

## 部署后验证（deploy 内置，用户要求项）

1. `127.0.0.1:7456/` → 401（应用活＋认证门生效）
2. `https://opendesign.xieyucheng.top/` → 401（隧道＋TLS＋应用全通；页面无 mixed-content）
3. 网关：无 key 200（对齐上游 models 无 key 可读）、有 key 200 且模型数正常（OD 后端依赖）
4. OD 日志 200 行内无 `litellm/gateway/ECONNREFUSED/model_not_found`（脱敏 grep，不打密钥）
5. 登录态（浏览器进模型列表）CI 无 token 做不了，由用户在浏览器确认

## 欠账（本次不动）

* 同 tag 双仓 digest 不同：`0.24.1-oc2.0.6` 在 GHCR 与 SWR 是两次构建（run 38830435447 实证 `manifest unknown`）。正源以 SWR 为准（线上跑的就是），CI boot 用 GHCR 版验定义，精确字节由 deploy pull 锁定。SWR 凭证配好后 CI 自动加验 pin 可拉取。
* ollama 真 digest：SWR 侧 `sha256:c401721b…`（取证到），`stacks/litellm-gateway` 里还是 docker hub 的 `adca95a…`，另起 PR 对账。
* OD 镜像 `<none>` 悬空 ID `8c7e518448ac` 留在 HW21（疑似某次重建残留），观察期清理。
