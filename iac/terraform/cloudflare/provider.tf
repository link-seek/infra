terraform {
  required_version = ">= 1.5"
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

# 状态/密钥不进仓：api_token 由 CI（org secret CF_PARENT_TOKEN 现签或专用 scoped token）注入。
# 采用已有资源见 ../README.md 的 cf-terraforming 步骤。
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
