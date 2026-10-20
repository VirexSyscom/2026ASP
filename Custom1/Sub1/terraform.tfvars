############################################
# terraform.tfvars
############################################

############################################
# 訂閱：由 Azure DevOps Service Connection 注入
# ARM_SUBSCRIPTION_ID，一般不需填寫
############################################
# subscription_id = "00000000-0000-0000-0000-000000000000"

############################################
# 命名前綴（Spoke / PROD-HR / UAT-HR / Migrate 共用）
############################################
name_prefix    = "demo"
name_separator = "-"

############################################
# 基本設定
############################################
location       = "japaneast"
location_short = "jpe"

############################################
# 四個資源群組（名稱皆不套用前綴）
############################################
network_resource_group_name   = "Spoke-Network-RG"
create_network_resource_group = true

hr_resource_group_name   = "Spoke-HR-RG"
create_hr_resource_group = true

uat_hr_resource_group_name   = "UAT-Spoke-HR-RG"
create_uat_hr_resource_group = true

# 遷移工具層：新增資源一律放在此資源群組
migrate_resource_group_name   = "AzureMigrateRG"
create_migrate_resource_group = true

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

# 分層專屬標籤

network_tags = {}

hr_tags = {
  Application = "HR-System"
}

uat_hr_tags = {
  Application = "HR-System"
  Purpose     = "UAT"
}

migrate_tags = {
  Application = "HR-System"
  Purpose     = "Migration"
}

############################################
# 網路位址 - Spoke（PROD / UAT）
############################################
spoke_vnet_address_space     = ["10.10.0.0/16"]
uat_spoke_vnet_address_space = ["10.20.0.0/16"]

ap_subnet_prefix           = "10.10.1.0/24"
db_subnet_prefix           = "10.10.2.0/24"
pe_subnet_prefix           = "10.10.3.0/24"
migrate_subnet_prefix      = "10.10.4.0/24"   # DMS 專用，建於既有 Spoke-VNET
bastion_subnet_prefix      = "10.10.250.0/26" # Developer SKU 下不會被使用
uat_workload_subnet_prefix = "10.20.1.0/24"
uat_pe_subnet_prefix       = "10.20.2.0/24"

############################################
# Bastion
############################################
bastion_sku           = "Developer"
create_bastion_subnet = false

############################################
# 運算
############################################
vm_names = ["cm-hr-01", "cm-hr-02"]
vm_size  = "Standard_D2s_v5"

uat_vm_name           = "cm-hr-test"
uat_vm_size           = "Standard_D2s_v5"
uat_data_disk_size_gb = 128

admin_username = "azureadmin"
admin_password = "@Dmin9487"

############################################
# 資料庫
############################################
sql_administrator_login    = "sqladminuser"
sql_administrator_password = "@Dmin9487"

sql_database_sku         = "S0"
sql_database_max_size_gb = 10

uat_sql_database_sku         = "S0"
uat_sql_database_max_size_gb = 10

############################################
# 儲存體（UAT）
############################################
storage_replication_type          = "LRS"
create_uat_eventgrid_system_topic = true

############################################
# 遷移工具層（AzureMigrateRG）
#   對應入口網站六項資源：
#     Migrate-HR                 -> Azure Migrate 專案（azapi 2020-05-01）
#     discovervmware4949vault    -> 復原服務保存庫
#     Migrate-HR8786kv           -> 金鑰保存庫
#     migratelog                 -> 儲存體帳戶
#     migratelog-<guid>          -> 事件方格系統主題
#     SQLtoAzureSQL              -> Database Migration Service
############################################
migrate_project_name = "Migrate-HR"

recovery_vault_name                = "discovervmware"
recovery_vault_sku                 = "Standard"
recovery_vault_storage_mode        = "LocallyRedundant"
recovery_vault_soft_delete_enabled = true

migrate_key_vault_name                          = "migratehr"
migrate_key_vault_sku                           = "standard"
migrate_key_vault_public_network_access_enabled = false
migrate_key_vault_purge_protection_enabled      = false

migrate_storage_name                          = "migratelog"
migrate_storage_replication_type              = "LRS"
migrate_storage_public_network_access_enabled = false
create_migrate_eventgrid_system_topic         = true

# Azure DevOps 服務連線的 SPN 若僅有 Contributor，必須維持 false，
# 否則會出現 403 AuthorizationFailed（roleAssignments/write）。
# SPN 具備 Role Based Access Control Administrator 時才可改為 true。
create_migrate_role_assignment = false

create_database_migration_service = true
database_migration_service_name   = "SQLtoAzureSQL"
database_migration_service_sku    = "Standard_1vCores"

############################################
# 監控
#   alert_action_group_id 留空時，網路活動記錄警示
#   會自動沿用 PROD HR 的 Email Action Group
############################################
alert_email           = "virex_lai@syscom.com.tw"
alert_action_group_id = ""
cpu_alert_threshold   = 80
dtu_alert_threshold   = 80
