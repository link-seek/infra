# Terraform state 后端：华为云 OBS（S3 兼容）。
# 统一桶 linkseek（cn-north-9），不同用途用不同前缀目录：本文件用 iac/cloudflare/。
# 凭据由 CI 以 AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY（= PROD_HCLOUD_AK/SK）注入，不入仓。
# 注意：OBS 特定桶操作要求 virtual-host 风格（否则报 VirtualHostDomainRequired），故 use_path_style=false。
terraform {
  backend "s3" {
    bucket = "linkseek"
    key    = "iac/cloudflare/terraform.tfstate"
    region = "cn-north-9"
    endpoints = {
      s3 = "https://obs.cn-north-9.myhuaweicloud.com"
    }
    # OBS 与 AWS S3 的细节差异：关掉这些校验/额外请求。
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
    use_path_style              = false
  }
}
