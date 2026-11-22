# IaC：Cloudflare（Terraform）+ 主机（Ansible）

目标（对应 infra #150「直管全场」）：把**云资源**与**主机配置**写进仓、可对账，替代散落的自研脚本。原则：**先只读对账（plan / --check），人工确认再 apply**。

## 目录
```
iac/terraform/cloudflare/
  provider.tf        # 官方 cloudflare/cloudflare provider（v5）
  backend.tf         # state 存 OBS（S3 兼容，唯一桶 linkseek 的 iac/cloudflare/ 前缀）
  dns.tf             # 41 条 DNS 记录（由生产实况生成，接管后的唯一声明源）
  main.tf            # 预留（zone/Workers/Pages 后续）
  variables.tf
iac/ansible/
  ansible.cfg
  inventory/hosts.yml            # 5 台主机（经 tailnet）
  playbooks/check-baseline.yml   # 只读基线巡检（--check）
.github/workflows/
  iac-check.yml          # PR 只做 fmt/validate + ansible syntax-check（不连线上）
  iac-adopt-cloudflare.yml  # dispatch：只读生成 DNS 的 .tf 制品（接管前用）
  iac-cloudflare.yml     # dispatch：plan / adopt(import) / apply（需人工 confirm）
  iac-host-check.yml     # dispatch：进 tailnet 跑 ansible --check（只读）
```

## 接管已有资源（一次性）
- DNS/zone 已有。**cf-terraforming 对 provider v5 的 `cloudflare_dns_record` 有长期未修的 nil-pointer panic**（上游 #956/#916），故改用 **Terraform 原生**：
  1. Cloudflare API 只读枚举各 zone 的全部 DNS 记录（含分页）。
  2. 生成 `import { to = cloudflare_dns_record.<x>; id = "<zone_id>/<record_id>" }` 块。
  3. `terraform plan -generate-config-out=generated.tf` 产出 HCL（read-only）。
  4. 核对 `Plan: N to import, 0 to add, 0 to change, 0 to destroy`。
  5. 提交配置（`dns.tf`）→ `iac-cloudflare.yml` mode=adopt 执行 import（apply 只写 state，不改线上）。
- 接管后 `terraform plan` 无差异＝已收敛；之后有差异＝漂移。
- **DNS 变更唯一流程**：改 `dns.tf` → `iac-cloudflare.yml` mode=plan（只读、人工看）→ mode=apply。旧 `dns/records.json` / `dns-apply` 已删除，只认本流程。

## 密钥
- `cloudflare_api_token` 由 CI 用 `CF_PARENT_TOKEN` 注入（`TF_VAR_cloudflare_api_token`，勿入仓）。
- Terraform state 存项目唯一 OBS 桶 `linkseek` 的 `iac/cloudflare/` 前缀（etcd 快照同桶 etcd-auto/）（凭据用 `PROD_HCLOUD_AK/SK`）。
- 主机侧敏感值走 Infisical（已建），不落仓。

## 阶段
1. 只读对账（plan / --check）。
2. CF DNS 接管（本仓 `dns.tf` 已就绪，待 mode=adopt import）。
3. 主机配置逐步 Ansible 化（systemd/包/文件/cloudflared/tailscale）。
