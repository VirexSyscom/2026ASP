############################################
# terraform.tfvars
#   Hub-Network-RG 獨立版本
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
name_prefix    = "demo"
name_separator = "-"

############################################
# 基本設定
############################################
location = "japaneast"

############################################
# 資源群組（名稱不套用前綴）
############################################
hub_resource_group_name   = "Hub-Network-RG"
create_hub_resource_group = true

############################################
# 標籤
############################################
environment = "prod"
owner       = "network-team"
cost_center = "CC-1001"

# 全域共用自訂標籤（同名時覆寫系統標籤）
tags = {
  Project      = "Hub-Spoke-Network"
  BusinessUnit = "HR"
  DataClass    = "Confidential"
  Criticality  = "High"
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
# Bastion 公用 IP（hub-vnet-bastion-IPaddress）
############################################
create_hub_bastion_public_ip = true

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

# create_vpn_connection = true 時，vpn_shared_key 必填
# 建議以環境變數注入：TF_VAR_vpn_shared_key
create_vpn_connection = false
# vpn_shared_key      = "***"

############################################
# 監控：Entra-Risky-SignIn
#   create_log_analytics_workspace = true  → 於 Hub RG 內建立專屬工作區（完全獨立）
#   create_log_analytics_workspace = false → 需填 log_analytics_workspace_id
#   alert_action_group_id 留空 → 警示不綁定任何 Action Group
############################################
create_risky_signin_alert      = true
create_log_analytics_workspace = true
log_analytics_workspace_id     = ""
log_analytics_retention_days   = 30

alert_action_group_id = ""

risky_signin_alert_severity  = 1
risky_signin_alert_frequency = "PT5M"
risky_signin_alert_window    = "PT5M"
