# Terraform state 后端：华为云 OBS（S3 兼容）。
# 统一桶 linkseek（cn-north-9，项目唯一 OBS 桶）：etcd 快照用 etcd-auto/，Terraform state 用 iac/。
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
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
    use_path_style              = false
  }
}
