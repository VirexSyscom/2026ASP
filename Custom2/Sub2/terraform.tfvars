############################################
# terraform.tfvars
############################################

############################################
# 訂閱：由 Azure DevOps Service Connection 注入
# ARM_SUBSCRIPTION_ID，一般不需填寫
############################################
# subscription_id = "00000000-0000-0000-0000-000000000000"

############################################
# 命名前綴
#   留空可保留圖片中的既有名稱；若填入 "demo"，
#   可自訂資源會變成 demo-<原始名稱>。
#   GatewaySubnet / AzureBastionSubnet / AzureManagedDomain 因 Azure 規則不加前綴。
############################################
name_prefix    = ""
name_separator = "-"

############################################
# 基本設定與兩個資源群組
############################################
location = "japaneast"

management_resource_group_name   = "Hub-Mgmt-RG"
create_management_resource_group = true

network_resource_group_name   = "Hub-Network-RG"
create_network_resource_group = true

############################################
# 標籤
############################################
environment = "prod"
owner       = "network-team"
cost_center = "CC-1001"

tags = {
  Project      = "Hub-Spoke-Network"
  BusinessUnit = "Shared-Services"
  DataClass    = "Confidential"
  Criticality  = "High"
  ReviewDate   = "2027-01-01"
}

management_tags = {
  Purpose = "Management-Automation-Backup"
}

network_tags = {
  Purpose = "Hub-Connectivity"
}

############################################
# Hub VNet / Bastion / VPN
############################################
hub_vnet_address_space = ["10.0.0.0/16"]
gateway_subnet_prefix  = "10.0.0.0/27"
bastion_subnet_prefix  = "10.0.0.64/26"

bastion_sku    = "Standard"
vpn_gateway_sku = "VpnGw1"

# 重要：203.0.113.10 是 RFC 5737 文件範例位址，部署前必須替換。
vpn_peer_public_ip   = "203.0.113.10"
onprem_address_spaces = ["192.168.0.0/16"]

# 建議由 Azure DevOps secret 變數 TF_VAR_vpn_shared_key 覆寫。
# 留白時由 random_password 產生，需同步設定至地端 VPN 裝置。
# vpn_shared_key = "<由 TF_VAR_vpn_shared_key 覆寫>"

############################################
# Recovery Services Vault
############################################
recovery_vault_sku                 = "Standard"
recovery_vault_storage_mode        = "LocallyRedundant"
recovery_vault_soft_delete_enabled = true

############################################
# Communication Services
############################################
communication_data_location = "Asia Pacific"

############################################
# API connections
#   圖片未包含驗證參數；請依實際連接器補值，並以 Secret 變數覆寫。
############################################
acs_email_managed_api_name = "azurecommunicationservicesemail"
azurevm_managed_api_name    = "azurevm"

acs_email_connection_parameter_values = {}
azurevm_connection_parameter_values    = {}

############################################
# Logic Apps / Service Health
############################################
logic_apps_enabled          = true
service_health_alert_enabled = true
alert_action_group_id       = ""
