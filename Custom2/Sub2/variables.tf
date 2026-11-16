############################################
# variables.tf
#   兩個資源群組統一採用：
#     <層>_resource_group_name / create_<層>_resource_group / <層>_tags
#       management：Hub-Mgmt-RG
#       network   ：Hub-Network-RG
############################################

############################################
# 訂閱與命名前綴
############################################
variable "subscription_id" {
  description = "Azure 訂閱 ID。留 null 由 ARM_SUBSCRIPTION_ID 環境變數提供。"
  type        = string
  default     = null
  nullable    = true
}

variable "name_prefix" {
  description = "所有可自訂資源名稱的前綴詞。留空則保留入口網站現況名稱；資源群組名稱不套用前綴。"
  type        = string
  default     = ""

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
# 基本設定與資源群組
############################################
variable "location" {
  description = "區域型資源部署位置"
  type        = string
  default     = "japaneast"
}

variable "management_resource_group_name" {
  description = "管理、監控、備份、Bastion、自動化及 Communication Services 資源群組名稱"
  type        = string
  default     = "Hub-Mgmt-RG"
}

variable "create_management_resource_group" {
  description = "true = 由本組態建立 Hub-Mgmt-RG；false = 沿用既有資源群組"
  type        = bool
  default     = true
}

variable "network_resource_group_name" {
  description = "Hub VNet 與 Site-to-Site VPN 資源群組名稱"
  type        = string
  default     = "Hub-Network-RG"
}

variable "create_network_resource_group" {
  description = "true = 由本組態建立 Hub-Network-RG；false = 沿用既有資源群組"
  type        = bool
  default     = true
}

############################################
# 標籤
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
  description = "成本中心代碼；留空則不輸出 CostCenter 標籤"
  type        = string
  default     = ""
}

variable "tags" {
  description = "全域共用自訂標籤；同名時覆寫系統標籤"
  type        = map(string)
  default     = {}
}

variable "management_tags" {
  description = "僅套用於 Hub-Mgmt-RG 內資源的額外標籤"
  type        = map(string)
  default     = {}
}

variable "network_tags" {
  description = "僅套用於 Hub-Network-RG 內資源的額外標籤"
  type        = map(string)
  default     = {}
}

############################################
# Hub VNet / Bastion / VPN
############################################
variable "hub_vnet_address_space" {
  description = "Hub-VNET 位址空間"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "gateway_subnet_prefix" {
  description = "GatewaySubnet 位址範圍"
  type        = string
  default     = "10.0.0.0/27"
}

variable "bastion_subnet_prefix" {
  description = "AzureBastionSubnet 位址範圍；Standard Bastion 建議至少 /26"
  type        = string
  default     = "10.0.0.64/26"
}

variable "bastion_sku" {
  description = "Azure Bastion SKU"
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.bastion_sku)
    error_message = "bastion_sku 必須為 Basic、Standard 或 Premium。"
  }
}

variable "vpn_gateway_sku" {
  description = "Virtual Network Gateway SKU"
  type        = string
  default     = "VpnGw1"
}

variable "vpn_peer_public_ip" {
  description = "地端 VPN 裝置的公用 IPv4 位址；部署前必須替換 terraform.tfvars 中的文件範例位址。"
  type        = string
  default     = "203.0.113.10"
}

variable "onprem_address_spaces" {
  description = "地端網路位址空間"
  type        = list(string)
  default     = ["192.168.0.0/16"]
}

variable "vpn_shared_key" {
  description = "Site-to-Site VPN 預共用金鑰。留 null 時由 random_password 產生並保存於 Terraform state。"
  type        = string
  default     = null
  nullable    = true
  sensitive   = true
}

############################################
# Recovery Services Vault
############################################
variable "recovery_vault_sku" {
  description = "CRM-Backup 復原服務保存庫 SKU"
  type        = string
  default     = "Standard"
}

variable "recovery_vault_storage_mode" {
  description = "CRM-Backup 儲存體複寫模式"
  type        = string
  default     = "LocallyRedundant"

  validation {
    condition     = contains(["LocallyRedundant", "GeoRedundant", "ZoneRedundant"], var.recovery_vault_storage_mode)
    error_message = "recovery_vault_storage_mode 必須為 LocallyRedundant、GeoRedundant 或 ZoneRedundant。"
  }
}

variable "recovery_vault_soft_delete_enabled" {
  description = "CRM-Backup 是否啟用虛刪除"
  type        = bool
  default     = true
}

############################################
# Communication Services
############################################
variable "communication_data_location" {
  description = "Communication Services 資料落地區域；Japan East 通常使用 Asia Pacific"
  type        = string
  default     = "Asia Pacific"
}

############################################
# API connections
#   圖片僅提供連線名稱，未包含驗證參數。
#   請依實際 Managed API 的 connectionParameters 填入敏感值，勿提交 Git。
############################################
variable "acs_email_managed_api_name" {
  description = "acsemail-2 對應的 Azure Managed API 名稱"
  type        = string
  default     = "azurecommunicationservicesemail"
}

variable "azurevm_managed_api_name" {
  description = "azurevm 對應的 Azure Managed API 名稱"
  type        = string
  default     = "azurevm"
}

variable "acs_email_connection_parameter_values" {
  description = "acsemail-2 API connection 的 parameterValues；實際鍵名依連接器驗證方式填入"
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "azurevm_connection_parameter_values" {
  description = "azurevm API connection 的 parameterValues；可依連接器驗證方式填入"
  type        = map(string)
  default     = {}
  sensitive   = true
}

############################################
# Logic Apps 與 Service Health 警示
############################################
variable "logic_apps_enabled" {
  description = "是否啟用 auto_start_vm 與 auto_stop_vm 工作流程。圖片未提供 definition，故先建立空白工作流程骨架。"
  type        = bool
  default     = true
}

variable "service_health_alert_enabled" {
  description = "是否啟用 Azure 服務健康狀態警示-Hub"
  type        = bool
  default     = true
}

variable "alert_action_group_id" {
  description = "服務健康狀態警示要通知的 Action Group 資源 ID；留空則不綁定通知"
  type        = string
  default     = ""
}
