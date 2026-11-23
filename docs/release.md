# 发布模型（docker-images → infra）

## 不变量

1. **制品不可变**：docker-images 每次 push main 产出一个不可变 tag `v<YYYY.MM.DD>-<short sha>`；同 tag 不同 digest 会让 workflow 红。
2. **制品只装部署清单**：artifact 内容 = `k8s/**`（忽略 `docker/ .github/ scripts/ docs/ *.md`），所以 **artifact digest 变化 == 一次部署变更**。
3. **infra pin digest**：`clusters/k3s/git-docker-images.yaml` 用 `ref.digest`（**manifest digest / Docker-Content-Digest**，不是 `status.artifact.digest`）。
4. **晋升 = 改 pin 的 PR**：docker-images 合 main 只产制品，不上生产；infra 改 digest 才上线。
5. **契约可校验**：`contract-check` 在 PR/push 时验证 pin 的 digest 真实存在于 SWR。

## 日常操作

升级一个发布：
1. docker-images 合 PR → 等 `flux-artifact` 成功
2. 从 run summary 取 `tag / digest`（格式：`ref: { digest: sha256:... }`）
3. infra PR 改 `git-docker-images.yaml` 的 `digest` + 注释 `# release: <tag>`（或等每周一 `release-bump` 自动开 draft PR）
4. `contract-check` 绿 → 合并 → Flux 5 分钟内对账

回滚：
- 把 `digest` 改回上一条 release 的 digest，提 PR 合并。git 历史即备份。

## 门禁

| 门 | 位置 | 状态 |
|---|---|---|
| 不可变 tag | docker-images `flux-artifact` | 硬（digest 不一致直接红） |
| 制品路径收窄 | docker-images `flux-artifact` | 硬 |
| pin digest 存在性 | infra `contract-check` | 硬 |
| 渲染产物 digest / 禁 latest | docker-images `policy` | **硬**（required check） |
| PR 需审批 | 两仓 branch protection | **已开**（required 1；`enforce_admins=false` 保留管理员紧急绕过） |

## system-upgrade

- 控制器已启用（`system-upgrade` ns，1/1）。
- `k3s-server` plan：控制面逐台，`concurrency: 1`。
- `k3s-agent` plan：**opt-in**，节点打 `system-upgrade.k3s.io/enabled=true` 才会参与（避免自动 drain 跑着 Traefik/egress 的边缘节点）。

## 已知边界

- `latest` 仍发布，但**生产不引用**；它只给预检/开发。
- 自动晋升（ImageUpdateAutomation / Renovate）尚未接入：当前 digest 由人从 run summary 取。后续接入后，本文件的“日常操作”第 2 步会消失。
