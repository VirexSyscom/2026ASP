############################################
# variables.tf
#   四個資源群組全部統一為同一套變數命名規則：
#     <層>_resource_group_name / create_<層>_resource_group / <層>_tags
#       network ：Spoke 網路（Spoke-VNET、NSG、NAT Gateway、路由表）
#       crm     ：Spoke-CRM-RG（VM、SQL 受控執行個體、Compute Gallery、監控）
#       migrate ：AzureMigrateRG 遷移工具層
#       adf     ：ADF-RG（Data Factory、Private Endpoint、Key Vault、儲存體）
############################################

############################################
# 訂閱
#   由 Azure DevOps Service Connection 自動注入
#   ARM_SUBSCRIPTION_ID，一般無需輸入。
############################################
variable "subscription_id" {
  description = "Azure 訂閱 ID。留 null 由 ARM_SUBSCRIPTION_ID 環境變數提供。"
  type        = string
  default     = null
  nullable    = true
}

############################################
# 命名前綴（四層共用同一套規則）
############################################
variable "name_prefix" {
  description = "所有資源名稱的前綴詞，例如 demo、crm、corp。留空則不加前綴。資源群組名稱不套用前綴。"
  type        = string
  default     = "demo"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]*$", var.name_prefix))
    error_message = "name_prefix 僅能包含英數字與連字號。"
  }

  validation {
    condition     = length(var.name_prefix) <= 10
    error_message = "name_prefix 建議不超過 10 字元，避免資源名稱超出 Azure 長度限制。"
  }
}

variable "name_separator" {
  description = "前綴與資源名稱之間的分隔符號"
  type        = string
  default     = "-"
}

############################################
# 基本設定
############################################
variable "location" {
  description = "資源部署區域"
  type        = string
  default     = "japaneast"
}

variable "location_short" {
  description = "區域縮寫，用於資源命名（japaneast = jpe）"
  type        = string
  default     = "jpe"
}

############################################
# 資源群組（四個獨立 RG，名稱皆不套用前綴）
############################################
variable "network_resource_group_name" {
  description = "Spoke 網路資源群組名稱（Spoke-VNET、NSG、NAT Gateway、路由表皆置於此）"
  type        = string
  default     = "Spoke-Network-RG"
}

variable "create_network_resource_group" {
  description = "true = 由本組態建立 Spoke 網路 RG；false = 沿用既有 RG"
  type        = bool
  default     = true
}

variable "crm_resource_group_name" {
  description = "CRM 工作負載資源群組名稱"
  type        = string
  default     = "Spoke-CRM-RG"
}

variable "create_crm_resource_group" {
  description = "true = 由本組態建立 CRM RG；false = 沿用既有 RG"
  type        = bool
  default     = true
}

variable "migrate_resource_group_name" {
  description = "遷移工具資源群組名稱（Azure Migrate / RSV / Key Vault / 儲存體皆置於此）"
  type        = string
  default     = "AzureMigrateRG"
}

variable "create_migrate_resource_group" {
  description = "true = 由本組態建立 AzureMigrateRG；false = 沿用既有 RG"
  type        = bool
  default     = true
}

variable "adf_resource_group_name" {
  description = "Azure Data Factory 資源群組名稱（Data Factory / Private Endpoint / Key Vault / 儲存體皆置於此）"
  type        = string
  default     = "ADF-RG"
}

variable "create_adf_resource_group" {
  description = "true = 由本組態建立 ADF-RG；false = 沿用既有 RG"
  type        = bool
  default     = true
}

############################################
# 標籤（統一由 locals 合併；資源群組名稱不加前綴，但標籤一律套用）
############################################
variable "environment" {
  description = "環境代號，會自動寫入 Environment 標籤"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["prod", "uat", "dev", "test"], var.environment)
    error_message = "environment 必須為 prod、uat、dev 或 test。"
  }
}

variable "owner" {
  description = "資源擁有者，會自動寫入 Owner 標籤"
  type        = string
  default     = "network-team"
}

variable "cost_center" {
  description = "成本中心代碼，會自動寫入 CostCenter 標籤；留空則不輸出該標籤"
  type        = string
  default     = ""
}

variable "tags" {
  description = "額外的全域自訂標籤，會與系統自動產生的共用標籤合併（同名時以此處為準）"
  type        = map(string)
  default     = {}
}

variable "network_tags" {
  description = "僅套用於 Spoke 網路資源群組資源的額外標籤"
  type        = map(string)
  default     = {}
}

variable "crm_tags" {
  description = "僅套用於 CRM 資源群組資源的額外標籤"
  type        = map(string)
  default     = {}
}

variable "migrate_tags" {
  description = "僅套用於 AzureMigrateRG 資源的額外標籤"
  type        = map(string)
  default     = {}
}

variable "adf_tags" {
  description = "僅套用於 ADF-RG 資源的額外標籤"
  type        = map(string)
  default     = {}
}

############################################
# 網路位址 - Spoke
############################################
variable "spoke_vnet_address_space" {
  description = "Spoke VNet 位址空間"
  type        = list(string)
  default     = ["10.10.0.0/16"]
}

variable "ap_subnet_prefix" {
  description = "應用程式子網路（CRM VM 與 CRMAP-LB 前端佈署於此）"
  type        = string
  default     = "10.10.1.0/24"
}

variable "mi_subnet_prefix" {
  description = "SQL 受控執行個體專用子網路（需委派給 Microsoft.Sql/managedInstances，且不可與其他資源共用）"
  type        = string
  default     = "10.10.2.0/24"
}

variable "pe_subnet_prefix" {
  description = "Private Endpoint 專用子網路（ADF-RG 的 Private Endpoint 佈署於此）"
  type        = string
  default     = "10.10.3.0/24"
}

############################################
# 運算（CRM）
#   兩台 VM 的 NIC / OS 磁碟名稱不同（對應入口網站現況），
#   因此以物件集合明確指定，而非單純的名稱集合。
############################################
variable "vms" {
  description = "CRM 虛擬機器定義（key 為內部識別，name / nic_name / os_disk_name 皆為基底名稱，實際名稱會自動加上前綴）"
  type = map(object({
    name         = string
    nic_name     = string
    os_disk_name = string
  }))
  default = {
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
}

variable "vm_size" {
  description = "CRM VM 規格"
  type        = string
  default     = "Standard_D2s_v5"
}

############################################
# 憑證
#   預設密碼為 Syscom2026（僅適用測試 / 展示環境）。
#   正式環境請改以 Azure DevOps 的 secret 變數覆寫：
#     TF_VAR_admin_password
#     TF_VAR_sql_administrator_password
############################################
variable "admin_username" {
  description = "VM 本機管理員帳號"
  type        = string
  default     = "azureadmin"
}

variable "admin_password" {
  description = "VM 本機管理員密碼。預設 Syscom2026；正式環境請以 TF_VAR_admin_password 或 Key Vault 覆寫。"
  type        = string
  default     = "Syscom2026"
  sensitive   = true
}

variable "sql_administrator_login" {
  description = "SQL 受控執行個體管理員帳號"
  type        = string
  default     = "sqladminuser"
}

variable "sql_administrator_password" {
  description = "SQL 受控執行個體管理員密碼。預設 Syscom2026；正式環境請以 TF_VAR_sql_administrator_password 或 Key Vault 覆寫。"
  type        = string
  default     = "Syscom2026"
  sensitive   = true
}

############################################
# Compute Gallery / 映像
############################################
variable "create_crm_image_version" {
  description = "是否建立映像版本 0.0.1。映像版本必須有來源，本組態會對 CRM VM 的 OS 磁碟建立一個快照（額外資源）作為來源。"
  type        = bool
  default     = true
}

variable "crm_image_version" {
  description = "Compute Gallery 映像版本號（語意化版本）"
  type        = string
  default     = "0.0.1"
}

############################################
# 磁碟：ASR 種子磁碟
#   asrseeddisk-* 原本由 Azure Site Recovery / Azure Migrate 在啟用複寫時自動建立
#   （Empty 磁碟）。此處保留以對齊現況資源；若不需要請設為 false。
############################################
variable "create_asr_seed_disk" {
  description = "是否建立 ASR 種子磁碟（空磁碟）"
  type        = bool
  default     = true
}

variable "asr_seed_disk_name" {
  description = "ASR 種子磁碟基底名稱（實際名稱會自動加上前綴）"
  type        = string
  default     = "asrseeddisk-CRM02-102_WS20-1c7dcf79-6c86-4f6d-8fd4-5306f3d3e70b"
}

variable "asr_seed_disk_size_gb" {
  description = "ASR 種子磁碟容量（GB）"
  type        = number
  default     = 128
}

variable "asr_seed_disk_storage_type" {
  description = "ASR 種子磁碟儲存體類型"
  type        = string
  default     = "Premium_LRS"
}

############################################
# SQL 受控執行個體（mssqlservermi）
############################################
variable "mi_name" {
  description = "SQL 受控執行個體基底名稱（實際名稱會自動加上緊湊前綴與亂數後綴，需全域唯一、僅限小寫英數字與連字號）"
  type        = string
  default     = "mssqlservermi"
}

variable "mi_sku_name" {
  description = "SQL 受控執行個體 SKU"
  type        = string
  default     = "GP_Gen5"
}

variable "mi_vcores" {
  description = "SQL 受控執行個體 vCore 數"
  type        = number
  default     = 4
}

variable "mi_storage_size_in_gb" {
  description = "SQL 受控執行個體儲存體容量（GB，須為 32 的倍數）"
  type        = number
  default     = 32
}

variable "mi_license_type" {
  description = "授權類型：LicenseIncluded 或 BasePrice（Azure Hybrid Benefit）"
  type        = string
  default     = "LicenseIncluded"

  validation {
    condition     = contains(["LicenseIncluded", "BasePrice"], var.mi_license_type)
    error_message = "mi_license_type 必須為 LicenseIncluded 或 BasePrice。"
  }
}

variable "crm_database_name" {
  description = "受控資料庫基底名稱（實際名稱會自動加上前綴）"
  type        = string
  default     = "CRMData"
}

############################################
# Azure Arc SQL Server（CRM-DB）
#   「Machine - Azure Arc」、「SQL Server 執行個體」與其資料庫
#   （CRMData / master / model / msdb / tempdb）原本由 Azure Arc Connected Machine Agent
#   與 SQL Server 擴充功能在實體主機上自動投影而成，並非一般 IaC 建立的資源。
#   預設關閉；設為 true 時以 azapi 直接建立 ARM 資源紀錄（僅是中繼資料，
#   不會真的連線到主機），請先確認 azapi 的 API 版本與屬性符合你的環境。
############################################
variable "create_arc_sql_resources" {
  description = "是否以 azapi 建立 Azure Arc 機器 / SQL Server 執行個體 / 資料庫的 ARM 資源紀錄"
  type        = bool
  default     = false
}

variable "arc_machine_name" {
  description = "Azure Arc 機器與 SQL Server 執行個體基底名稱（實際名稱會自動加上前綴）"
  type        = string
  default     = "CRM-DB"
}

variable "arc_sql_database_names" {
  description = "Arc SQL Server 執行個體下的資料庫名稱（資料庫名稱對應實際資料庫，不加前綴）"
  type        = set(string)
  default     = ["CRMData", "master", "model", "msdb", "tempdb"]
}

############################################
# 遷移層：Azure Migrate 專案
#   注意：Microsoft.Migrate/migrateProjects 在 japaneast 僅支援
#   2018-09-01-preview / 2019-06-01 / 2020-05-01 / 2020-06-01-preview，
#   本組態固定使用 2020-05-01（詳見 main.tf）。
############################################
variable "migrate_project_name" {
  description = "Azure Migrate 專案基底名稱（實際名稱會自動加上前綴）"
  type        = string
  default     = "Migrate-CRM"
}

############################################
# 遷移層：Recovery Services Vault
############################################
variable "recovery_vault_name" {
  description = "復原服務保存庫基底名稱（實際名稱會自動加上前綴、亂數後綴與 vault）"
  type        = string
  default     = "discovervmware"
}

variable "recovery_vault_sku" {
  description = "復原服務保存庫 SKU"
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "RS0"], var.recovery_vault_sku)
    error_message = "recovery_vault_sku 必須為 Standard 或 RS0。"
  }
}

variable "recovery_vault_storage_mode" {
  description = "復原服務保存庫儲存體複寫模式"
  type        = string
  default     = "LocallyRedundant"

  validation {
    condition     = contains(["LocallyRedundant", "GeoRedundant", "ZoneRedundant"], var.recovery_vault_storage_mode)
    error_message = "recovery_vault_storage_mode 必須為 LocallyRedundant、GeoRedundant 或 ZoneRedundant。"
  }
}

variable "recovery_vault_soft_delete_enabled" {
  description = "復原服務保存庫是否啟用虛刪除（Soft Delete）"
  type        = bool
  default     = true
}

############################################
# 遷移層：Key Vault
#   AzureMigrateRG 現況沒有 Private Endpoint，故預設允許公用網路存取。
############################################
variable "migrate_key_vault_name" {
  description = "遷移層 Key Vault 基底名稱（實際名稱會自動加上緊湊前綴、亂數後綴與 kv）"
  type        = string
  default     = "migratecrm"
}

variable "migrate_key_vault_sku" {
  description = "Key Vault SKU"
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "premium"], var.migrate_key_vault_sku)
    error_message = "migrate_key_vault_sku 必須為 standard 或 premium。"
  }
}

variable "migrate_key_vault_public_network_access_enabled" {
  description = "Key Vault 是否允許公用網路存取"
  type        = bool
  default     = true
}

variable "migrate_key_vault_purge_protection_enabled" {
  description = "Key Vault 是否啟用清除保護（啟用後無法提前刪除，請審慎評估）"
  type        = bool
  default     = false
}

############################################
# 遷移層：儲存體（migratecrmlog）
############################################
variable "migrate_storage_name" {
  description = "遷移記錄儲存體帳戶基底名稱（實際名稱會自動加上緊湊前綴與亂數後綴）"
  type        = string
  default     = "migratecrmlog"
}

variable "migrate_storage_replication_type" {
  description = "遷移記錄儲存體帳戶複寫類型"
  type        = string
  default     = "LRS"
}

variable "migrate_storage_public_network_access_enabled" {
  description = "遷移記錄儲存體帳戶是否允許公用網路存取"
  type        = bool
  default     = true
}

############################################
# ADF-RG：Data Factory / Key Vault / 儲存體 / NSG
############################################
variable "adf_name" {
  description = "Data Factory 基底名稱（實際名稱會自動加上前綴與亂數後綴，需全域唯一）"
  type        = string
  default     = "adfsyscom"
}

variable "adf_public_network_enabled" {
  description = "Data Factory 是否允許公用網路存取。false 時一律透過 Private Endpoint（adf-pe）連線"
  type        = bool
  default     = false
}

variable "adf_key_vault_name" {
  description = "ADF 自我裝載整合執行階段（SHIR）用 Key Vault 基底名稱（實際名稱會自動加上前綴與亂數後綴）"
  type        = string
  default     = "kv-gfs-shir"
}

variable "adf_key_vault_sku" {
  description = "ADF Key Vault SKU"
  type        = string
  default     = "standard"
}

variable "adf_key_vault_public_network_access_enabled" {
  description = "ADF Key Vault 是否允許公用網路存取。false 時一律透過 Private Endpoint（pe-kv-gfs-shir）連線"
  type        = bool
  default     = false
}

variable "adf_storage_name" {
  description = "ADF 儲存體帳戶基底名稱（實際名稱會自動加上緊湊前綴與亂數後綴；啟用階層命名空間以支援 dfs 端點）"
  type        = string
  default     = "jgfsshir01"
}

variable "adf_storage_replication_type" {
  description = "ADF 儲存體帳戶複寫類型"
  type        = string
  default     = "LRS"
}

variable "adf_nsg_name" {
  description = "ADF-RG 網路安全性群組基底名稱（沿用入口網站現況名稱 ADF-NSF）"
  type        = string
  default     = "ADF-NSF"
}

############################################
# 監控
#   現況沒有 Action Group；alert_action_group_id 留空時警示規則不綁定通知，
#   指定既有 Action Group 的資源 ID 後才會寄送通知。
############################################
variable "alert_action_group_id" {
  description = "警示規則要通知的 Action Group 資源 ID；留空則不綁定 Action Group"
  type        = string
  default     = ""
}

variable "cpu_alert_threshold" {
  description = "VM CPU 使用率警示門檻（%），同時會寫入警示名稱（Percentage CPU more <門檻>）"
  type        = number
  default     = 80
}
