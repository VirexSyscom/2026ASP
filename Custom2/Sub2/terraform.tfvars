############################################
# terraform.tfvars
############################################

############################################
# 訂閱：通常由 Azure DevOps Service Connection 注入
############################################
# subscription_id = "00000000-0000-0000-0000-000000000000"

############################################
# 命名與區域
# 留空以保留 Azure Portal 中的原始資源名稱
############################################
name_prefix    = ""
name_separator = "-"
location       = "japaneast"

############################################
# 資源群組
# 若 RG 已存在，請改為 false；既有資源仍需先執行 terraform import。
############################################
mgmt_resource_group_name   = "Hub-Mgmt-RG"
create_mgmt_resource_group = true

network_resource_group_name   = "Hub-Network-RG"
create_network_resource_group = true

############################################
# TAG
############################################
environment = "prod"
owner       = "platform-team"
cost_center = ""

tags = {
  Project     = "Hub-Spoke-Network"
  Criticality = "High"
}

mgmt_tags = {
  Service = "Management"
}

network_tags = {
  Service = "Connectivity"
}

############################################
# Hub VNet
# 部署前務必與既有 Spoke／地端網段核對，避免重疊。
############################################
hub_vnet_address_space = ["10.0.0.0/16"]
gateway_subnet_prefix  = "10.0.0.0/27"
bastion_subnet_prefix  = "10.0.0.64/26"

############################################
# Bastion / Public IP
############################################
public_ip_zones = []
bastion_sku     = "Standard"

############################################
# Site-to-Site VPN
# 203.0.113.10 是文件範例位址，部署前必須替換。
# PSK 建議由 Azure DevOps secret：TF_VAR_vpn_shared_key 注入。
############################################
vpn_gateway_sku        = "VpnGw1"
vpn_gateway_generation = "Generation1"
vpn_active_active      = false
vpn_enable_bgp         = false
vpn_peer_public_ip     = "203.0.113.10"
onprem_address_spaces  = ["192.168.0.0/16"]
# vpn_shared_key       = "<由 TF_VAR_vpn_shared_key 覆寫>"

############################################
# Recovery Services Vault
############################################
recovery_vault_sku                 = "Standard"
recovery_vault_storage_mode        = "LocallyRedundant"
recovery_vault_soft_delete_enabled = true

############################################
# Azure 服務健康狀態警示
############################################
service_health_locations = ["Global", "Japan East"]
