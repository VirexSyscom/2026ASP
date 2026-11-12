############################################
# terraform.tfvars
#   Hub-Network-RG 測試環境獨立版本
############################################

############################################
# 訂閱：由 Azure DevOps Service Connection 注入
# ARM_SUBSCRIPTION_ID，一般不需填寫
############################################
# subscription_id = "00000000-0000-0000-0000-000000000000"

############################################
# 命名前綴
#   設為 "" 時，資源名稱與入口網站現況完全相同
############################################
name_prefix    = "test"
name_separator = "-"

############################################
# 基本設定
############################################
location = "japaneast"

############################################
# 資源群組（名稱不套用前綴）
############################################
hub_resource_group_name = "Hub-Network-RG"

############################################
# 標籤
############################################
environment = "test"
owner       = "network-team"
cost_center = "CC-1001"

# 全域共用自訂標籤（同名時覆寫系統標籤）
tags = {
  Project      = "Hub-Spoke-Network"
  BusinessUnit = "HR"
  DataClass    = "Confidential"
  Criticality  = "Low"
  ReviewDate   = "2027-01-01"
}

# Hub 專屬標籤
hub_tags = {
  Workload = "Hub-Network"
}

############################################
# 網路位址 - Hub
############################################
hub_vnet_address_space  = ["10.0.0.0/16"]
gateway_subnet_prefixes = ["10.0.1.0/27"]

############################################
# VPN Gateway / Site-to-Site
############################################
create_vpn_gateway          = true
vpn_gateway_sku             = "VpnGw2AZ"
vpn_gateway_public_ip_zones = ["1", "2", "3"]
enable_bgp                  = false

onprem_vpn_public_ip = "203.0.113.10"
onprem_address_spaces = [
  "192.168.10.0/24",
  "192.168.20.0/24"
]

# 測試環境啟用 ToFortiVPN；VPN Shared Key 直接寫入此檔案
# 注意：此檔案含測試用敏感資訊，不可提交至公開版本庫
create_vpn_connection = true
vpn_shared_key        = "W5ugWgZzirnD5l1vD5ejGUfMWGvxvnsV"

