############################################
# variables.tf
#   四個資源群組全部統一為同一套變數命名規則：
#     <層>_resource_group_name / create_<層>_resource_group / <層>_tags
#       network ：Spoke 網路（PROD + UAT VNet）
#       hr      ：PROD HR 工作負載
#       uat_hr  ：UAT  HR 工作負載
#       migrate ：AzureMigrateRG 遷移工具層
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
# 命名前綴（五層共用同一套規則）
############################################
variable "name_prefix" {
  description = "所有資源名稱的前綴詞，例如 demo、hr、corp。留空則不加前綴。資源群組名稱不套用前綴。"
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
  description = "Spoke 網路資源群組名稱（PROD 與 UAT VNet 皆置於此）"
  type        = string
  default     = "Spoke-Network-RG"
}

variable "create_network_resource_group" {
  description = "true = 由本組態建立 Spoke 網路 RG；false = 沿用既有 RG"
  type        = bool
  default     = true
}

variable "hr_resource_group_name" {
  description = "PROD HR 工作負載資源群組名稱"
  type        = string
  default     = "Spoke-HR-RG"
}

variable "create_hr_resource_group" {
  description = "true = 由本組態建立 PROD HR RG；false = 沿用既有 RG"
  type        = bool
  default     = true
}

variable "uat_hr_resource_group_name" {
  description = "UAT HR 工作負載資源群組名稱"
  type        = string
  default     = "UAT-Spoke-HR-RG"
}

variable "create_uat_hr_resource_group" {
  description = "true = 由本組態建立 UAT HR RG；false = 沿用既有 RG"
  type        = bool
  default     = true
}

variable "migrate_resource_group_name" {
  description = "遷移工具資源群組名稱（Azure Migrate / RSV / Key Vault / 儲存體 / DMS 皆置於此）"
  type        = string
  default     = "AzureMigrateRG"
}

variable "create_migrate_resource_group" {
  description = "true = 由本組態建立 AzureMigrateRG；false = 沿用既有 RG"
  type        = bool
  default     = true
}

############################################
# 標籤（統一由 locals 合併；資源群組名稱不加前綴，但標籤一律套用）
############################################
variable "environment" {
  description = "環境代號，會自動寫入 Environment 標籤（UAT 層會自動改寫為 uat）"
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

variable "hr_tags" {
  description = "僅套用於 PROD HR 資源群組資源的額外標籤"
  type        = map(string)
  default     = {}
}

variable "uat_hr_tags" {
  description = "僅套用於 UAT HR 資源群組資源的額外標籤"
  type        = map(string)
  default     = {}
}

variable "migrate_tags" {
  description = "僅套用於 AzureMigrateRG 資源的額外標籤"
  type        = map(string)
  default     = {}
}

############################################
# 網路位址 - Spoke（PROD / UAT）
############################################
variable "spoke_vnet_address_space" {
  description = "正式 Spoke VNet 位址空間"
  type        = list(string)
  default     = ["10.10.0.0/16"]
}

variable "uat_spoke_vnet_address_space" {
  description = "UAT Spoke VNet 位址空間"
  type        = list(string)
  default     = ["10.20.0.0/16"]
}

variable "ap_subnet_prefix" {
  description = "應用程式子網路（PROD HR VM 佈署於此）"
  type        = string
  default     = "10.10.1.0/24"
}

variable "db_subnet_prefix" {
  description = "資料庫子網路"
  type        = string
  default     = "10.10.2.0/24"
}

variable "pe_subnet_prefix" {
  description = "PROD Private Endpoint 專用子網路（PROD HR SQL PE、遷移層 PE 佈署於此）"
  type        = string
  default     = "10.10.3.0/24"
}

variable "bastion_subnet_prefix" {
  description = "Spoke AzureBastionSubnet 至少需 /26（僅在 create_bastion_subnet = true 時使用）"
  type        = string
  default     = "10.10.250.0/26"
}

variable "uat_workload_subnet_prefix" {
  description = "UAT 工作負載子網路（UAT HR VM 佈署於此）"
  type        = string
  default     = "10.20.1.0/24"
}

variable "uat_pe_subnet_prefix" {
  description = "UAT Private Endpoint 專用子網路（UAT SQL / Storage PE 佈署於此）"
  type        = string
  default     = "10.20.2.0/24"
}

############################################
# 網路位址 - 遷移專用子網路（沿用 PROD Spoke-VNET）
#   Database Migration Service 需要一個「專屬委派子網路」，
#   不可與 AP / DB / PE 子網路共用。
############################################
variable "migrate_subnet_prefix" {
  description = "Database Migration Service 專用子網路（建立於既有的 PROD Spoke-VNET 內）"
  type        = string
  default     = "10.10.4.0/24"
}

############################################
# Bastion
############################################

variable "bastion_sku" {
  description = "Spoke Bastion SKU。Developer 免公用 IP、免 AzureBastionSubnet，但不支援 VNet peering 與並行連線"
  type        = string
  default     = "Developer"

  validation {
    condition     = contains(["Developer", "Basic", "Standard", "Premium"], var.bastion_sku)
    error_message = "bastion_sku 必須為 Developer、Basic、Standard 或 Premium。"
  }
}

variable "create_bastion_subnet" {
  description = "是否建立 Spoke 的 AzureBastionSubnet。Developer SKU 不需要，設為 false 可省去該子網路"
  type        = bool
  default     = false

  validation {
    condition     = !(var.bastion_sku != "Developer" && var.create_bastion_subnet == false)
    error_message = "Basic/Standard/Premium SKU 必須建立 AzureBastionSubnet，請將 create_bastion_subnet 設為 true。"
  }
}

############################################
# 運算（PROD HR）
############################################
variable "vm_names" {
  description = "PROD HR 虛擬機器基底名稱集合（實際名稱會自動加上前綴）"
  type        = set(string)
  default     = ["cm-hr-01", "cm-hr-02"]
}

variable "vm_size" {
  description = "PROD HR VM 規格"
  type        = string
  default     = "Standard_D2s_v5"
}

############################################
# 運算（UAT HR）
############################################
variable "uat_vm_name" {
  description = "UAT HR 虛擬機器基底名稱（實際名稱會自動加上前綴）"
  type        = string
  default     = "cm-hr-test"
}

variable "uat_vm_size" {
  description = "UAT HR VM 規格"
  type        = string
  default     = "Standard_D2s_v5"
}

variable "uat_data_disk_size_gb" {
  description = "UAT HR VM 掛載的資料磁碟容量（GB）"
  type        = number
  default     = 128
}

############################################
# 憑證（PROD / UAT 共用同一組帳密設定）
############################################
variable "admin_username" {
  description = "VM 本機管理員帳號"
  type        = string
  default     = "azureadmin"
}

variable "admin_password" {
  description = "VM 本機管理員密碼。正式環境建議改用 Key Vault 或 TF_VAR 環境變數注入。"
  type        = string
  sensitive   = true
  default     = "@Dmin9487"
}

variable "sql_administrator_login" {
  description = "Azure SQL 管理員帳號"
  type        = string
  default     = "sqladminuser"
}

variable "sql_administrator_password" {
  description = "Azure SQL 管理員密碼。正式環境建議改用 Key Vault 或 TF_VAR 環境變數注入。"
  type        = string
  sensitive   = true
  default     = "@Dmin9487"
}

############################################
# 資料庫
############################################
variable "sql_database_sku" {
  description = "PROD HR 資料庫 SKU"
  type        = string
  default     = "S0"
}

variable "sql_database_max_size_gb" {
  description = "PROD HR 資料庫容量上限（GB）"
  type        = number
  default     = 10
}

variable "uat_sql_database_sku" {
  description = "UAT HR 資料庫 SKU"
  type        = string
  default     = "S0"
}

variable "uat_sql_database_max_size_gb" {
  description = "UAT HR 資料庫容量上限（GB）"
  type        = number
  default     = 10
}

############################################
# 儲存體（UAT）
############################################
variable "storage_replication_type" {
  description = "UAT 儲存體帳戶複寫類型"
  type        = string
  default     = "LRS"
}

variable "create_uat_eventgrid_system_topic" {
  description = "是否為 UAT 儲存體帳戶建立 Event Grid System Topic"
  type        = bool
  default     = true
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
  default     = "Migrate-HR"
}

############################################
# 遷移層：Recovery Services Vault
############################################
variable "recovery_vault_name" {
  description = "復原服務保存庫基底名稱（實際名稱會自動加上前綴與亂數後綴）"
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
############################################
variable "migrate_key_vault_name" {
  description = "遷移層 Key Vault 基底名稱（實際名稱會自動加上前綴與亂數後綴）"
  type        = string
  default     = "migratehr"
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
  description = "Key Vault 是否允許公用網路存取。false 時一律透過 Private Endpoint 連線"
  type        = bool
  default     = false
}

variable "migrate_key_vault_purge_protection_enabled" {
  description = "Key Vault 是否啟用清除保護（啟用後無法提前刪除，請審慎評估）"
  type        = bool
  default     = false
}

############################################
# 遷移層：儲存體（migratelog）
############################################
variable "migrate_storage_name" {
  description = "遷移記錄儲存體帳戶基底名稱（實際名稱會自動加上緊湊前綴與亂數後綴）"
  type        = string
  default     = "migratelog"
}

variable "migrate_storage_replication_type" {
  description = "遷移記錄儲存體帳戶複寫類型"
  type        = string
  default     = "LRS"
}

variable "migrate_storage_public_network_access_enabled" {
  description = "遷移記錄儲存體帳戶是否允許公用網路存取。false 時一律透過 Private Endpoint 連線"
  type        = bool
  default     = false
}

variable "create_migrate_eventgrid_system_topic" {
  description = "是否為遷移記錄儲存體帳戶建立 Event Grid System Topic"
  type        = bool
  default     = true
}

############################################
# 遷移層：角色指派
#   Azure DevOps 服務連線通常僅具 Contributor，
#   不含 Microsoft.Authorization/roleAssignments/write，
#   會導致 403 AuthorizationFailed，故預設關閉。
#   若 SPN 具 Role Based Access Control Administrator
#   或 User Access Administrator，可改為 true。
############################################
variable "create_migrate_role_assignment" {
  description = "是否由 Terraform 建立 RSV 對遷移儲存體的角色指派。SPN 需具備 RBAC 管理權限才能設為 true。"
  type        = bool
  default     = false
}

############################################
# 遷移層：Database Migration Service
############################################
variable "create_database_migration_service" {
  description = "是否建立 Azure Database Migration Service（傳統版 DMS 已宣告淘汰，新專案建議改用 Azure SQL 移轉延伸模組）"
  type        = bool
  default     = true
}

variable "database_migration_service_name" {
  description = "Database Migration Service 基底名稱（實際名稱會自動加上前綴）"
  type        = string
  default     = "SQLtoAzureSQL"
}

variable "database_migration_service_sku" {
  description = "Database Migration Service SKU"
  type        = string
  default     = "Standard_1vCores"

  validation {
    condition = contains([
      "Standard_1vCores", "Standard_2vCores", "Standard_4vCores", "Premium_4vCores"
    ], var.database_migration_service_sku)
    error_message = "請指定有效的 DMS SKU。"
  }
}

############################################
# 監控
############################################
variable "alert_email" {
  description = "監控警示收件者（PROD 與 UAT 共用）"
  type        = string
  default     = "ops@example.com"
}

variable "alert_action_group_id" {
  description = "網路活動記錄警示要通知的 Action Group 資源 ID；留空則自動改用 PROD HR 的 Email Action Group"
  type        = string
  default     = ""
}

variable "cpu_alert_threshold" {
  description = "VM CPU 使用率警示門檻（%）"
  type        = number
  default     = 80
}

variable "dtu_alert_threshold" {
  description = "SQL DTU 使用率警示門檻（%）"
  type        = number
  default     = 80
}
