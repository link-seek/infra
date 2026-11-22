variable "cloudflare_api_token" {
  description = "Cloudflare API token（由 CI secret 注入，勿写入 tfvars/仓）"
  type        = string
  sensitive   = true
}
