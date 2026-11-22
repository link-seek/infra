# =============================================================================
# Cloudflare DNS 记录 —— Terraform 接管（唯一声明源）
# -----------------------------------------------------------------------------
# 生成方式：2026-11-22 由生产实况生成（Cloudflare API 只读枚举 41 条 → import 块 →
#   terraform plan -generate-config-out），并已核对 `Plan: 41 to import,
#   0 to add, 0 to change, 0 to destroy`（即配置=现网，无差异）。
#
# ⚠️ 接管后本文件是这些 DNS 记录的唯一真相源：
#   - 不要再改 dns/records*.json 用 dns-apply 去改同一批记录（会造成双源头冲突）。
#   - DNS 变更流程：改本文件 → CI 跑 `terraform plan`（只读、人工确认）→ apply。
#
# 首次接管（把现有记录 import 进 state）：见 iac/README.md 的 "接管" 一节，
#   使用 .github/workflows/iac-cloudflare.yml 的 mode=adopt（会临时生成 import 块，
#   apply 仅 import、不改线上；plan 已证 0 变更）。state 存 OBS(S3) 见 backend.tf。
# =============================================================================


# __generated__ by Terraform from "f46e66f694af4a9e8f8830d0673822b9/7430f68e7a94cc405797a5df3dfe053e"
resource "cloudflare_dns_record" "xieyucheng_top_7" {
  comment                 = "od:cfp:0962de0bfe35:9815b89902de"
  content                 = "od-new-generation-default-scenario-39f033fc-968.pages.dev"
  data                    = null
  include_shadow_metadata = false
  name                    = "benchmarktable.xieyucheng.top"
  priority                = null
  private_routing         = null
  proxied                 = true
  settings = {
    flatten_cname = false
    ipv4_only     = false
    ipv6_only     = false
  }
  tags    = []
  ttl     = 1
  type    = "CNAME"
  zone_id = "f46e66f694af4a9e8f8830d0673822b9"
}

# __generated__ by Terraform from "f46e66f694af4a9e8f8830d0673822b9/0df65535246f56687baf12b447812d0b"
resource "cloudflare_dns_record" "xieyucheng_top_5" {
  comment                 = null
  content                 = "ffc3e65b-b970-44ca-ad8b-866b643d515d.cfargotunnel.com"
  data                    = null
  include_shadow_metadata = false
  name                    = "api.xieyucheng.top"
  priority                = null
  private_routing         = null
  proxied                 = true
  settings = {
    flatten_cname = false
    ipv4_only     = false
    ipv6_only     = false
  }
  tags    = []
  ttl     = 1
  type    = "CNAME"
  zone_id = "f46e66f694af4a9e8f8830d0673822b9"
}

# __generated__ by Terraform from "f46e66f694af4a9e8f8830d0673822b9/29f8646f556b17222ce7d7abb3802f24"
resource "cloudflare_dns_record" "xieyucheng_top_15" {
  comment                 = "od:cfp:95b22839077f:b218d5952bdc"
  content                 = "od-new-generation-default-scenario-e85a55a9-f5a.pages.dev"
  data                    = null
  include_shadow_metadata = false
  name                    = "todo.xieyucheng.top"
  priority                = null
  private_routing         = null
  proxied                 = true
  settings = {
    flatten_cname = false
    ipv4_only     = false
    ipv6_only     = false
  }
  tags    = []
  ttl     = 1
  type    = "CNAME"
  zone_id = "f46e66f694af4a9e8f8830d0673822b9"
}

# __generated__ by Terraform from "4cdd8779bc924de8f682abf0a765f51c/58fc4635f51b3a13b750b452ab3f23a0"
resource "cloudflare_dns_record" "linkseek_net_cn_3" {
  comment                 = "od:cfp:cdb2adbfcc7e:a3dde0f286e5"
  content                 = "od-project-11f47c98-eb6.pages.dev"
  data                    = null
  include_shadow_metadata = false
  name                    = "3003.linkseek.net.cn"
  priority                = null
  private_routing         = null
  proxied                 = true
  settings = {
    flatten_cname = false
    ipv4_only     = false
    ipv6_only     = false
  }
  tags    = []
  ttl     = 1
  type    = "CNAME"
  zone_id = "4cdd8779bc924de8f682abf0a765f51c"
}

# __generated__ by Terraform from "f46e66f694af4a9e8f8830d0673822b9/67ee0404949dfb5e41f683af5e948006"
resource "cloudflare_dns_record" "xieyucheng_top_1" {
  comment                 = null
  content                 = "120.77.76.20"
  data                    = null
  include_shadow_metadata = false
  name                    = "home-oc.xieyucheng.top"
  priority                = null
  private_routing         = null
  proxied                 = false
  settings = {
    flatten_cname = null
    ipv4_only     = null
    ipv6_only     = null
  }
  tags    = []
  ttl     = 600
  type    = "A"
  zone_id = "f46e66f694af4a9e8f8830d0673822b9"
}

# __generated__ by Terraform from "02cdd0bade03819592958c6ecb67cdd2/85a4dd286833a861a90550f9c05ee2f5"
resource "cloudflare_dns_record" "yingxin_net_cn_1" {
  comment                 = null
  content                 = "100::"
  data                    = null
  include_shadow_metadata = false
  name                    = "www.yingxin.net.cn"
  priority                = null
  private_routing         = null
  proxied                 = true
  settings = {
    flatten_cname = null
    ipv4_only     = null
    ipv6_only     = null
  }
  tags    = []
  ttl     = 1
  type    = "AAAA"
  zone_id = "02cdd0bade03819592958c6ecb67cdd2"
}

# __generated__ by Terraform from "f46e66f694af4a9e8f8830d0673822b9/e2aa070cad65580fb9a9204bc4d46771"
resource "cloudflare_dns_record" "xieyucheng_top_9" {
  comment                 = "od:cfp:976964260fd8:4a042f516a69"
  content                 = "od-cloudflare-homelab-5a70bf1d-ba6.pages.dev"
  data                    = null
  include_shadow_metadata = false
  name                    = "cf-tunnel.xieyucheng.top"
  priority                = null
  private_routing         = null
  proxied                 = true
  settings = {
    flatten_cname = false
    ipv4_only     = false
    ipv6_only     = false
  }
  tags    = []
  ttl     = 1
  type    = "CNAME"
  zone_id = "f46e66f694af4a9e8f8830d0673822b9"
}

# __generated__ by Terraform from "f46e66f694af4a9e8f8830d0673822b9/71c24c8a4b57808a641e9525da7165dd"
resource "cloudflare_dns_record" "xieyucheng_top_4" {
  comment                 = null
  content                 = "120.77.76.20"
  data                    = null
  include_shadow_metadata = false
  name                    = "team-agent.xieyucheng.top"
  priority                = null
  private_routing         = null
  proxied                 = false
  settings = {
    flatten_cname = null
    ipv4_only     = null
    ipv6_only     = null
  }
  tags    = []
  ttl     = 600
  type    = "A"
  zone_id = "f46e66f694af4a9e8f8830d0673822b9"
}

# __generated__ by Terraform from "02cdd0bade03819592958c6ecb67cdd2/5cbb240df9b6b5413e98cbba3e4208f7"
resource "cloudflare_dns_record" "yingxin_net_cn_0" {
  comment                 = null
  content                 = "120.77.76.20"
  data                    = null
  include_shadow_metadata = false
  name                    = "opencode.yingxin.net.cn"
  priority                = null
  private_routing         = null
  proxied                 = false
  settings = {
    flatten_cname = null
    ipv4_only     = null
    ipv6_only     = null
  }
  tags    = []
  ttl     = 600
  type    = "A"
  zone_id = "02cdd0bade03819592958c6ecb67cdd2"
}

# __generated__ by Terraform from "4cdd8779bc924de8f682abf0a765f51c/8a7e7452d52cdf669c5ca7de09027e46"
resource "cloudflare_dns_record" "linkseek_net_cn_0" {
  comment                 = null
  content                 = "192.0.2.1"
  data                    = null
  include_shadow_metadata = false
  name                    = "linkseek.net.cn"
  priority                = null
  private_routing         = null
  proxied                 = true
  settings = {
    flatten_cname = null
    ipv4_only     = null
    ipv6_only     = null
  }
  tags    = []
  ttl     = 1
  type    = "A"
  zone_id = "4cdd8779bc924de8f682abf0a765f51c"
}

# __generated__ by Terraform from "f46e66f694af4a9e8f8830d0673822b9/21294254d01af7896d1f33345062845e"
resource "cloudflare_dns_record" "xieyucheng_top_8" {
  comment                 = "od:cfp:cdcd0750f421:6558869227a3"
  content                 = "od-benchmark-e3b7805b-292.pages.dev"
  data                    = null
  include_shadow_metadata = false
  name                    = "benchmark.xieyucheng.top"
  priority                = null
  private_routing         = null
  proxied                 = true
  settings = {
    flatten_cname = false
    ipv4_only     = false
    ipv6_only     = false
  }
  tags    = []
  ttl     = 1
  type    = "CNAME"
  zone_id = "f46e66f694af4a9e8f8830d0673822b9"
}

# __generated__ by Terraform from "f46e66f694af4a9e8f8830d0673822b9/2acfa34258377a95216ff7cb51ce9251"
resource "cloudflare_dns_record" "xieyucheng_top_6" {
  comment                 = null
  content                 = "cname.vercel-dns.com"
  data                    = null
  include_shadow_metadata = false
  name                    = "baby.xieyucheng.top"
  priority                = null
  private_routing         = null
  proxied                 = false
  settings = {
    flatten_cname = false
    ipv4_only     = false
    ipv6_only     = false
  }
  tags    = []
  ttl     = 600
  type    = "CNAME"
  zone_id = "f46e66f694af4a9e8f8830d0673822b9"
}

# __generated__ by Terraform from "4cdd8779bc924de8f682abf0a765f51c/44e27dd8af467b23c4cb639c860a7c99"
resource "cloudflare_dns_record" "linkseek_net_cn_16" {
  comment                 = "od:cfp:b010f58f5a45:e736500335f3"
  content                 = "od-project-5377d351-fe5.pages.dev"
  data                    = null
  include_shadow_metadata = false
  name                    = "tianlong.linkseek.net.cn"
  priority                = null
  private_routing         = null
  proxied                 = true
  settings = {
    flatten_cname = false
    ipv4_only     = false
    ipv6_only     = false
  }
  tags    = []
  ttl     = 1
  type    = "CNAME"
  zone_id = "4cdd8779bc924de8f682abf0a765f51c"
}

# __generated__ by Terraform from "4cdd8779bc924de8f682abf0a765f51c/4be759fb447ccca15602bc48e0f56be2"
resource "cloudflare_dns_record" "linkseek_net_cn_13" {
  comment                 = "pilot worker route #706"
  content                 = "pilot-consumer.workers.dev"
  data                    = null
  include_shadow_metadata = false
  name                    = "pilot-api.linkseek.net.cn"
  priority                = null
  private_routing         = null
  proxied                 = true
  settings = {
    flatten_cname = false
    ipv4_only     = false
    ipv6_only     = false
  }
  tags    = []
  ttl     = 1
  type    = "CNAME"
  zone_id = "4cdd8779bc924de8f682abf0a765f51c"
}

# __generated__ by Terraform from "f46e66f694af4a9e8f8830d0673822b9/85d78b5cc3035334b09e3291e1c2d879"
resource "cloudflare_dns_record" "xieyucheng_top_16" {
  comment                 = null
  content                 = "verify_91805b22ed486baccbd64b847425c88e"
  data                    = null
  include_shadow_metadata = false
  name                    = "verification.xieyucheng.top"
  priority                = null
  private_routing         = null
  proxied                 = false
  settings = {
    flatten_cname = null
    ipv4_only     = null
    ipv6_only     = null
  }
  tags    = []
  ttl     = 600
  type    = "TXT"
  zone_id = "f46e66f694af4a9e8f8830d0673822b9"
}

# __generated__ by Terraform from "f46e66f694af4a9e8f8830d0673822b9/1603a6bbaa01722289e0500e51c584b7"
resource "cloudflare_dns_record" "xieyucheng_top_11" {
  comment                 = "od:cfp:9d4302036b47:37f666da0646"
  content                 = "od-project-af9320bb-bfe.pages.dev"
  data                    = null
  include_shadow_metadata = false
  name                    = "kehui-a.xieyucheng.top"
  priority                = null
  private_routing         = null
  proxied                 = true
  settings = {
    flatten_cname = false
    ipv4_only     = false
    ipv6_only     = false
  }
  tags    = []
  ttl     = 1
  type    = "CNAME"
  zone_id = "f46e66f694af4a9e8f8830d0673822b9"
}

# __generated__ by Terraform from "4cdd8779bc924de8f682abf0a765f51c/256efa90d411dc0eb3eae7b971fd4c3d"
resource "cloudflare_dns_record" "linkseek_net_cn_2" {
  comment                 = null
  content                 = "192.0.2.1"
  data                    = null
  include_shadow_metadata = false
  name                    = "sdk.linkseek.net.cn"
  priority                = null
  private_routing         = null
  proxied                 = true
  settings = {
    flatten_cname = null
    ipv4_only     = null
    ipv6_only     = null
  }
  tags    = []
  ttl     = 1
  type    = "A"
  zone_id = "4cdd8779bc924de8f682abf0a765f51c"
}

# __generated__ by Terraform from "f46e66f694af4a9e8f8830d0673822b9/ce1235b7dbd114c4438ea396f0470da1"
resource "cloudflare_dns_record" "xieyucheng_top_14" {
  comment                 = "od:cfp:b010f58f5a45:e736500335f3"
  content                 = "od-project-5377d351-fe5.pages.dev"
  data                    = null
  include_shadow_metadata = false
  name                    = "tianlong.xieyucheng.top"
  priority                = null
  private_routing         = null
  proxied                 = true
  settings = {
    flatten_cname = false
    ipv4_only     = false
    ipv6_only     = false
  }
  tags    = []
  ttl     = 1
  type    = "CNAME"
  zone_id = "f46e66f694af4a9e8f8830d0673822b9"
}

# __generated__ by Terraform from "f46e66f694af4a9e8f8830d0673822b9/807d87999bd4d36f82c0ff843085444e"
resource "cloudflare_dns_record" "xieyucheng_top_18" {
  comment                 = null
  content                 = "100::"
  data                    = null
  include_shadow_metadata = false
  name                    = "xieyucheng.top"
  priority                = null
  private_routing         = null
  proxied                 = true
  settings = {
    flatten_cname = null
    ipv4_only     = null
    ipv6_only     = null
  }
  tags    = []
  ttl     = 1
  type    = "AAAA"
  zone_id = "f46e66f694af4a9e8f8830d0673822b9"
}

# __generated__ by Terraform from "4cdd8779bc924de8f682abf0a765f51c/abaff26abdcd52dc562e0fe594f9e07b"
resource "cloudflare_dns_record" "linkseek_net_cn_17" {
  comment                 = null
  content                 = "100::"
  data                    = null
  include_shadow_metadata = false
  name                    = "pi-lite.linkseek.net.cn"
  priority                = null
  private_routing         = null
  proxied                 = true
  settings = {
    flatten_cname = null
    ipv4_only     = null
    ipv6_only     = null
  }
  tags    = []
  ttl     = 1
  type    = "AAAA"
  zone_id = "4cdd8779bc924de8f682abf0a765f51c"
}

# __generated__ by Terraform from "02cdd0bade03819592958c6ecb67cdd2/da4e565545e75babe2f128f98c5c9f92"
resource "cloudflare_dns_record" "yingxin_net_cn_2" {
  comment                 = null
  content                 = "100::"
  data                    = null
  include_shadow_metadata = false
  name                    = "yingxin.net.cn"
  priority                = null
  private_routing         = null
  proxied                 = true
  settings = {
    flatten_cname = null
    ipv4_only     = null
    ipv6_only     = null
  }
  tags    = []
  ttl     = 1
  type    = "AAAA"
  zone_id = "02cdd0bade03819592958c6ecb67cdd2"
}

# __generated__ by Terraform from "4cdd8779bc924de8f682abf0a765f51c/ee029d3a718c26b40d0b23598003638f"
resource "cloudflare_dns_record" "linkseek_net_cn_8" {
  comment                 = null
  content                 = "ffc3e65b-b970-44ca-ad8b-866b643d515d.cfargotunnel.com"
  data                    = null
  include_shadow_metadata = false
  name                    = "eap-api.linkseek.net.cn"
  priority                = null
  private_routing         = null
  proxied                 = true
  settings = {
    flatten_cname = false
    ipv4_only     = false
    ipv6_only     = false
  }
  tags    = []
  ttl     = 1
  type    = "CNAME"
  zone_id = "4cdd8779bc924de8f682abf0a765f51c"
}

# __generated__ by Terraform from "4cdd8779bc924de8f682abf0a765f51c/cac1aac576e09c48f42b384755a06ce2"
resource "cloudflare_dns_record" "linkseek_net_cn_6" {
  comment                 = "od:cfp:f58c3033991c:f228ae7c7598"
  content                 = "od-project-0d665757-112.pages.dev"
  data                    = null
  include_shadow_metadata = false
  name                    = "coperation.linkseek.net.cn"
  priority                = null
  private_routing         = null
  proxied                 = true
  settings = {
    flatten_cname = false
    ipv4_only     = false
    ipv6_only     = false
  }
  tags    = []
  ttl     = 1
  type    = "CNAME"
  zone_id = "4cdd8779bc924de8f682abf0a765f51c"
}

# __generated__ by Terraform from "f46e66f694af4a9e8f8830d0673822b9/0d5e559a954f067db20deacfa5c7ebab"
resource "cloudflare_dns_record" "xieyucheng_top_0" {
  comment                 = null
  content                 = "120.77.76.20"
  data                    = null
  include_shadow_metadata = false
  name                    = "erp.xieyucheng.top"
  priority                = null
  private_routing         = null
  proxied                 = false
  settings = {
    flatten_cname = null
    ipv4_only     = null
    ipv6_only     = null
  }
  tags    = []
  ttl     = 600
  type    = "A"
  zone_id = "f46e66f694af4a9e8f8830d0673822b9"
}

# __generated__ by Terraform from "4cdd8779bc924de8f682abf0a765f51c/5587c409897fcde336f60ac17ce61b14"
resource "cloudflare_dns_record" "linkseek_net_cn_9" {
  comment                 = null
  content                 = "eap-frontend.pages.dev"
  data                    = null
  include_shadow_metadata = false
  name                    = "eap.linkseek.net.cn"
  priority                = null
  private_routing         = null
  proxied                 = true
  settings = {
    flatten_cname = false
    ipv4_only     = false
    ipv6_only     = false
  }
  tags    = []
  ttl     = 1
  type    = "CNAME"
  zone_id = "4cdd8779bc924de8f682abf0a765f51c"
}

# __generated__ by Terraform from "f46e66f694af4a9e8f8830d0673822b9/c32195b6b11dfd82bfac9ecdb50b4b2a"
resource "cloudflare_dns_record" "xieyucheng_top_2" {
  comment                 = null
  content                 = "120.77.76.20"
  data                    = null
  include_shadow_metadata = false
  name                    = "opencode.xieyucheng.top"
  priority                = null
  private_routing         = null
  proxied                 = false
  settings = {
    flatten_cname = null
    ipv4_only     = null
    ipv6_only     = null
  }
  tags    = []
  ttl     = 600
  type    = "A"
  zone_id = "f46e66f694af4a9e8f8830d0673822b9"
}

# __generated__ by Terraform from "f46e66f694af4a9e8f8830d0673822b9/4761866a2b78bbc964244d82886b7fec"
resource "cloudflare_dns_record" "xieyucheng_top_12" {
  comment                 = "od:cfp:9d4302036b47:37f666da0646"
  content                 = "od-project-af9320bb-bfe.pages.dev"
  data                    = null
  include_shadow_metadata = false
  name                    = "kehui-b.xieyucheng.top"
  priority                = null
  private_routing         = null
  proxied                 = true
  settings = {
    flatten_cname = false
    ipv4_only     = false
    ipv6_only     = false
  }
  tags    = []
  ttl     = 1
  type    = "CNAME"
  zone_id = "f46e66f694af4a9e8f8830d0673822b9"
}

# __generated__ by Terraform from "4cdd8779bc924de8f682abf0a765f51c/f3683079417171e1b9f7c7429224cd63"
resource "cloudflare_dns_record" "linkseek_net_cn_15" {
  comment                 = null
  content                 = "fc0b47fa-3339-4985-a2ba-d85574e34ace.cfargotunnel.com"
  data                    = null
  include_shadow_metadata = false
  name                    = "ssh-21-test.linkseek.net.cn"
  priority                = null
  private_routing         = null
  proxied                 = true
  settings = {
    flatten_cname = false
    ipv4_only     = false
    ipv6_only     = false
  }
  tags    = []
  ttl     = 1
  type    = "CNAME"
  zone_id = "4cdd8779bc924de8f682abf0a765f51c"
}

# __generated__ by Terraform from "4cdd8779bc924de8f682abf0a765f51c/2b38251625fec0dc91be5efdd5bee073"
resource "cloudflare_dns_record" "linkseek_net_cn_7" {
  comment                 = "od:cfp:d8db0b3ce8a8:2d22276d1ebe"
  content                 = "od-new-generation-default-scenario-4addeba9-261.pages.dev"
  data                    = null
  include_shadow_metadata = false
  name                    = "design.linkseek.net.cn"
  priority                = null
  private_routing         = null
  proxied                 = true
  settings = {
    flatten_cname = false
    ipv4_only     = false
    ipv6_only     = false
  }
  tags    = []
  ttl     = 1
  type    = "CNAME"
  zone_id = "4cdd8779bc924de8f682abf0a765f51c"
}

# __generated__ by Terraform from "4cdd8779bc924de8f682abf0a765f51c/bfa53caa99341f0496980a7bb83e4107"
resource "cloudflare_dns_record" "linkseek_net_cn_1" {
  comment                 = null
  content                 = "120.77.76.20"
  data                    = null
  include_shadow_metadata = false
  name                    = "litellm.linkseek.net.cn"
  priority                = null
  private_routing         = null
  proxied                 = false
  settings = {
    flatten_cname = null
    ipv4_only     = null
    ipv6_only     = null
  }
  tags    = []
  ttl     = 600
  type    = "A"
  zone_id = "4cdd8779bc924de8f682abf0a765f51c"
}

# __generated__ by Terraform from "f46e66f694af4a9e8f8830d0673822b9/113535a094fa064b1a741ab568c69db4"
resource "cloudflare_dns_record" "xieyucheng_top_10" {
  comment                 = "od:cfp:611b413a2c59:002ea842e9ec"
  content                 = "od-project-3e368bc1-7ba.pages.dev"
  data                    = null
  include_shadow_metadata = false
  name                    = "eai-01.xieyucheng.top"
  priority                = null
  private_routing         = null
  proxied                 = true
  settings = {
    flatten_cname = false
    ipv4_only     = false
    ipv6_only     = false
  }
  tags    = []
  ttl     = 1
  type    = "CNAME"
  zone_id = "f46e66f694af4a9e8f8830d0673822b9"
}

# __generated__ by Terraform from "4cdd8779bc924de8f682abf0a765f51c/9194a0cce97113b662da9d15466112cb"
resource "cloudflare_dns_record" "linkseek_net_cn_5" {
  comment                 = null
  content                 = "cfos-demo.pages.dev"
  data                    = null
  include_shadow_metadata = false
  name                    = "cfos.linkseek.net.cn"
  priority                = null
  private_routing         = null
  proxied                 = false
  settings = {
    flatten_cname = false
    ipv4_only     = false
    ipv6_only     = false
  }
  tags    = []
  ttl     = 600
  type    = "CNAME"
  zone_id = "4cdd8779bc924de8f682abf0a765f51c"
}

# __generated__ by Terraform from "f46e66f694af4a9e8f8830d0673822b9/a6b13a13fa3f81d37a5e72e18e2503e6"
resource "cloudflare_dns_record" "xieyucheng_top_3" {
  comment                 = null
  content                 = "168.110.36.240"
  data                    = null
  include_shadow_metadata = false
  name                    = "proxy.xieyucheng.top"
  priority                = null
  private_routing         = null
  proxied                 = false
  settings = {
    flatten_cname = null
    ipv4_only     = null
    ipv6_only     = null
  }
  tags    = []
  ttl     = 600
  type    = "A"
  zone_id = "f46e66f694af4a9e8f8830d0673822b9"
}

# __generated__ by Terraform from "4cdd8779bc924de8f682abf0a765f51c/2f5965674e977cf70bf80ee2de3c7fe2"
resource "cloudflare_dns_record" "linkseek_net_cn_18" {
  comment                 = null
  content                 = "100::"
  data                    = null
  include_shadow_metadata = false
  name                    = "www.linkseek.net.cn"
  priority                = null
  private_routing         = null
  proxied                 = true
  settings = {
    flatten_cname = null
    ipv4_only     = null
    ipv6_only     = null
  }
  tags    = []
  ttl     = 1
  type    = "AAAA"
  zone_id = "4cdd8779bc924de8f682abf0a765f51c"
}

# __generated__ by Terraform from "4cdd8779bc924de8f682abf0a765f51c/fac7a8e64c1387aa02b06b5a766d0f87"
resource "cloudflare_dns_record" "linkseek_net_cn_14" {
  comment                 = "pilot frontend #706"
  content                 = "pilot-consumer.pages.dev"
  data                    = null
  include_shadow_metadata = false
  name                    = "pilot.linkseek.net.cn"
  priority                = null
  private_routing         = null
  proxied                 = true
  settings = {
    flatten_cname = false
    ipv4_only     = false
    ipv6_only     = false
  }
  tags    = []
  ttl     = 1
  type    = "CNAME"
  zone_id = "4cdd8779bc924de8f682abf0a765f51c"
}

# __generated__ by Terraform from "4cdd8779bc924de8f682abf0a765f51c/7375a26053a4e861a415be295ce7a4a7"
resource "cloudflare_dns_record" "linkseek_net_cn_4" {
  comment                 = "od:cfp:cdcd0750f421:6558869227a3"
  content                 = "od-benchmark-e3b7805b-292.pages.dev"
  data                    = null
  include_shadow_metadata = false
  name                    = "benchmark.linkseek.net.cn"
  priority                = null
  private_routing         = null
  proxied                 = true
  settings = {
    flatten_cname = false
    ipv4_only     = false
    ipv6_only     = false
  }
  tags    = []
  ttl     = 1
  type    = "CNAME"
  zone_id = "4cdd8779bc924de8f682abf0a765f51c"
}

# __generated__ by Terraform from "f46e66f694af4a9e8f8830d0673822b9/657b4dc05bf2b1beac06f4d474523db1"
resource "cloudflare_dns_record" "xieyucheng_top_17" {
  comment                 = null
  content                 = "100::"
  data                    = null
  include_shadow_metadata = false
  name                    = "www.xieyucheng.top"
  priority                = null
  private_routing         = null
  proxied                 = true
  settings = {
    flatten_cname = null
    ipv4_only     = null
    ipv6_only     = null
  }
  tags    = []
  ttl     = 1
  type    = "AAAA"
  zone_id = "f46e66f694af4a9e8f8830d0673822b9"
}
