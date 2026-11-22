# IaC：Cloudflare（Terraform）+ 主机（Ansible）

目标（对应 infra #150「直管全场」）：把**云资源**与**主机配置**也"写进仓、可对账"，替代散落的自研脚本。原则：**先只读对账（plan / --check），人工确认再 apply**。

## 目录
```
iac/terraform/cloudflare/   # Cloudflare：DNS/zone/Workers/Pages（官方 cloudflare/cloudflare provider）
iac/ansible/                # 主机：inventory + 只读基线巡检 playbook
.github/workflows/iac-check.yml  # PR 时只做 fmt/validate/syntax-check（不连线上）
```

## 接管已有资源（一次性，官方工具）
- DNS/zone 已有 → 用官方 **cf-terraforming** 生成配置与 import：
  ```bash
  CF_API_TOKEN=<scoped token> cf-terraforming generate \
    --resource-type cloudflare_dns_record \
    --zone <zone_id> > main.tf
  # 再为每条生成 import 块后 terraform import；或 cf-terraforming import --resource-type ... 
  ```
  接管后 `terraform plan` 无差异＝已收敛；之后 plan 有差异＝漂移。
- 主机：`ansible-playbook -i inventory/hosts.yml playbooks/check-baseline.yml --check` 只读采集；逐步把 systemd/包/文件写成 playbook。

## 密钥
- `cloudflare_api_token` 由 CI secret 注入（勿入仓）；Terraform state 不入仓（本地/CI 临时，或后续放 OBS/SWR）。
- 主机侧敏感值走 Infisical（已建），不落仓。

## 阶段
1. 只读对账（plan / --check）+ 定时漂移报告（漂了开 issue）。
2. CF zone/Workers/Pages 全量接管（Terraform）。
3. 主机配置逐步 Ansible 化（systemd/包/文件/cloudflared/tailscale）。
