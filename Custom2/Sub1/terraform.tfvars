############################################
# terraform.tfvars
############################################

############################################
# 訂閱：由 Azure DevOps Service Connection 注入
# ARM_SUBSCRIPTION_ID，一般不需填寫
############################################
# subscription_id = "00000000-0000-0000-0000-000000000000"

############################################
# 命名前綴（Spoke / CRM / Migrate / ADF 共用）
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

crm_resource_group_name   = "Spoke-CRM-RG"
create_crm_resource_group = true

# 遷移工具層：新增資源一律放在此資源群組
migrate_resource_group_name   = "AzureMigrateRG"
create_migrate_resource_group = true

adf_resource_group_name   = "ADF-RG"
create_adf_resource_group = true

############################################
# 標籤
############################################
environment = "prod"
owner       = "network-team"
cost_center = "CC-1001"

# 全域共用自訂標籤（同名時覆寫系統標籤）
tags = {
  Project      = "Hub-Spoke-Network"
  BusinessUnit = "CRM"
  DataClass    = "Confidential"
  Criticality  = "High"
  ReviewDate   = "2027-01-01"
}

# 分層專屬標籤
network_tags = {}

crm_tags = {
  Application = "CRM-System"
}

migrate_tags = {
  Application = "CRM-System"
  Purpose     = "Migration"
}

adf_tags = {
  Application = "Data-Factory"
  Purpose     = "SHIR"
}

############################################
# 網路位址 - Spoke
############################################
spoke_vnet_address_space = ["10.10.0.0/16"]

ap_subnet_prefix = "10.10.1.0/24"
mi_subnet_prefix = "10.10.2.0/24" # SQL 受控執行個體專用（委派子網路）
pe_subnet_prefix = "10.10.3.0/24"

############################################
# 運算（CRM）
############################################
vms = {
  crm = {
    name         = "CRM"
    nic_name     = "nic-CRM-00"
    os_disk_name = "CRM-OSdisk-00"
  }
  crm02 = {
    name         = "CRM02"
    nic_name     = "crm02743"
    os_disk_name = "CRM02_OsDisk_1_12296849cc664ff8907594924475f8cc"
  }
}

vm_size        = "Standard_D2s_v5"
admin_username = "azureadmin"

############################################
# 憑證
#   未指定時由 random_password 產生 24 碼高強度亂數，並固定於 Terraform state。
#   如需自行指定，請由 Azure DevOps secret 變數覆寫，勿寫入 Git：
#     TF_VAR_admin_password
#     TF_VAR_sql_administrator_password
#   無法使用亂數時，可改用 Syscom2026 的合規變種（至少 12 碼）。
############################################
# admin_password             = "<由 TF_VAR_admin_password 覆寫>"
# sql_administrator_password = "<由 TF_VAR_sql_administrator_password 覆寫>"
sql_administrator_login = "sqladminuser"

############################################
# Compute Gallery / 映像
############################################
create_crm_image_version = true
crm_image_version        = "0.0.1"

############################################
# ASR 種子磁碟
############################################
create_asr_seed_disk       = true
asr_seed_disk_name         = "asrseeddisk-CRM02-102_WS20-1c7dcf79-6c86-4f6d-8fd4-5306f3d3e70b"
asr_seed_disk_size_gb      = 128
asr_seed_disk_storage_type = "Premium_LRS"

############################################
# SQL 受控執行個體
############################################
mi_name               = "mssqlservermi"
mi_sku_name           = "GP_Gen5"
mi_vcores             = 4
mi_storage_size_in_gb = 32
mi_license_type       = "LicenseIncluded"
crm_database_name     = "CRMData"

############################################
# Azure SQL logical server + 5 個 Azure SQL Database
#   沿用 CRM RG、共用前綴、local.crm_tags 與 SQL 管理員帳密。
############################################
sql_server_base_name                     = "crm-sql"
sql_database_names                       = ["CRMData", "CRMApp", "CRMArchive", "CRMReporting", "CRMStaging"]
sql_database_sku_name                    = "Basic"
sql_database_max_size_gb                 = 2
sql_database_collation                   = "SQL_Latin1_General_CP1_CI_AS"
sql_server_public_network_access_enabled = false

############################################
# Azure Arc SQL Server
#   true = 以 azapi 建立 Arc 機器 / SQL Server 執行個體 / 5 個資料庫的資源紀錄，
#          不需真實主機連線；顯示的版本與狀態皆為下方靜態值。
#   部署前請先註冊 Microsoft.HybridCompute 與 Microsoft.AzureArcData。
############################################
create_arc_sql_resources = true
arc_machine_name         = "CRM-DB"
arc_sql_edition          = "Standard"
arc_sql_version          = "SQL Server 2022"
arc_sql_status           = "Connected"
arc_sql_database_names   = ["CRMData", "master", "model", "msdb", "tempdb"]

############################################
# 遷移工具層（AzureMigrateRG）
#   對應入口網站四項資源：
#     Migrate-CRM              -> Azure Migrate 專案（azapi 2020-05-01）
#     discovervmware8406vault  -> 復原服務保存庫
#     Migrate-CRM5539kv        -> 金鑰保存庫
#     migratecrmlog            -> 儲存體帳戶
############################################
migrate_project_name = "Migrate-CRM"

recovery_vault_name                = "discovervmware"
recovery_vault_sku                 = "Standard"
recovery_vault_storage_mode        = "LocallyRedundant"
recovery_vault_soft_delete_enabled = true

migrate_key_vault_name                          = "migratecrm"
migrate_key_vault_sku                           = "standard"
migrate_key_vault_public_network_access_enabled = true
migrate_key_vault_purge_protection_enabled      = false

migrate_storage_name                          = "migratecrmlog"
migrate_storage_replication_type              = "LRS"
migrate_storage_public_network_access_enabled = true

############################################
# ADF-RG
#   adfsyscom / kv-gfs-shir-yxqvj / jgfsshir01 / ADF-NSF
############################################
adf_name                   = "adfsyscom"
adf_public_network_enabled = false

adf_key_vault_name                          = "kv-gfs-shir"
adf_key_vault_sku                           = "standard"
adf_key_vault_public_network_access_enabled = false

adf_storage_name             = "jgfsshir01"
adf_storage_replication_type = "LRS"

adf_nsg_name = "ADF-NSF"

############################################
# 監控
#   現況沒有 Action Group；指定既有 Action Group 的資源 ID 後才會寄送通知
#   cpu_alert_threshold = 1 對應入口網站現有警示「Percentage CPU more 1」
############################################
alert_action_group_id = ""
cpu_alert_threshold   = 1
