############################################
# variables.tf
#   兩個資源群組：
#     mgmt    ：Bastion、備份、服務健康警示
#     network ：Hub VNet 與 Site-to-Site VPN
############################################

############################################
# 訂閱與命名
############################################
variable "subscription_id" {
  description = "Azure 訂閱 ID。留 null 時由 ARM_SUBSCRIPTION_ID 提供。"
  type        = string
  default     = null
  nullable    = true
}

variable "name_prefix" {
  description = "資源名稱前綴；留空會保留 Azure Portal 畫面中的原始名稱。資源群組與保留名稱子網路不加前綴。"
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]*$", var.name_prefix))
    error_message = "name_prefix 僅能包含英數字與連字號。"
  }
}

variable "name_separator" {
  description = "名稱前綴與基底名稱之間的分隔符號。"
  type        = string
  default     = "-"
}

############################################
# 基本設定與資源群組
############################################
variable "location" {
  description = "Azure 部署區域。"
  type        = string
  default     = "japaneast"
}

variable "mgmt_resource_group_name" {
  description = "管理資源群組名稱；不套用名稱前綴。"
  type        = string
  default     = "Hub-Mgmt-RG"
}

variable "create_mgmt_resource_group" {
  description = "true = 建立 Hub-Mgmt-RG；false = 沿用既有資源群組。"
  type        = bool
  default     = true
}

variable "network_resource_group_name" {
  description = "Hub 網路資源群組名稱；不套用名稱前綴。"
  type        = string
  default     = "Hub-Network-RG"
}

variable "create_network_resource_group" {
  description = "true = 建立 Hub-Network-RG；false = 沿用既有資源群組。"
  type        = bool
  default     = true
}

############################################
# TAG
############################################
variable "environment" {
  description = "環境標籤。"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["prod", "uat", "dev", "test"], var.environment)
    error_message = "environment 必須為 prod、uat、dev 或 test。"
  }
}

variable "owner" {
  description = "資源擁有者標籤。"
  type        = string
  default     = "platform-team"
}

variable "cost_center" {
  description = "成本中心標籤；留空則不輸出。"
  type        = string
  default     = ""
}

variable "tags" {
  description = "套用到所有資源的自訂標籤；同名時覆寫系統標籤。"
  type        = map(string)
  default     = {}
}

variable "mgmt_tags" {
  description = "僅套用到 Hub-Mgmt-RG 資源的額外標籤。"
  type        = map(string)
  default     = {}
}

variable "network_tags" {
  description = "僅套用到 Hub-Network-RG 資源的額外標籤。"
  type        = map(string)
  default     = {}
}

############################################
# Hub VNet 與子網路
############################################
variable "hub_vnet_address_space" {
  description = "Hub VNet 位址空間。"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "gateway_subnet_prefix" {
  description = "GatewaySubnet 位址範圍。"
  type        = string
  default     = "10.0.0.0/27"
}

variable "bastion_subnet_prefix" {
  description = "AzureBastionSubnet 位址範圍；建議至少 /26。"
  type        = string
  default     = "10.0.0.64/26"
}

############################################
# Public IP 與 Bastion
############################################
variable "public_ip_zones" {
  description = "Public IP 可用區；空集合表示區域性且不指定 zone。"
  type        = list(string)
  default     = []
}

variable "bastion_sku" {
  description = "Azure Bastion SKU。"
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.bastion_sku)
    error_message = "bastion_sku 必須為 Basic、Standard 或 Premium。"
  }
}

############################################
# Site-to-Site VPN
############################################
variable "vpn_gateway_sku" {
  description = "Virtual Network Gateway SKU。"
  type        = string
  default     = "VpnGw1"
}

variable "vpn_gateway_generation" {
  description = "VPN Gateway generation。"
  type        = string
  default     = "Generation1"

  validation {
    condition     = contains(["Generation1", "Generation2", "None"], var.vpn_gateway_generation)
    error_message = "vpn_gateway_generation 必須為 Generation1、Generation2 或 None。"
  }
}

variable "vpn_active_active" {
  description = "是否啟用 active-active VPN Gateway。"
  type        = bool
  default     = false
}

variable "vpn_enable_bgp" {
  description = "是否啟用 BGP。"
  type        = bool
  default     = false
}

variable "vpn_peer_public_ip" {
  description = "FortiGate／地端 VPN 裝置的真實公用 IP。部署前必須替換預設文件範例位址。"
  type        = string
  default     = "203.0.113.10"
}

variable "onprem_address_spaces" {
  description = "地端網路位址範圍。"
  type        = list(string)
  default     = ["192.168.0.0/16"]
}

variable "vpn_shared_key" {
  description = "Site-to-Site VPN PSK。null 時產生 32 碼亂數；可用 TF_VAR_vpn_shared_key 覆寫。"
  type        = string
  default     = null
  nullable    = true
  sensitive   = true

  validation {
    condition     = var.vpn_shared_key == null ? true : length(var.vpn_shared_key) >= 16
    error_message = "vpn_shared_key 若有指定，長度至少須為 16 個字元。"
  }
}

############################################
# Recovery Services Vault
############################################
variable "recovery_vault_sku" {
  description = "CRM-Backup 的 Recovery Services Vault SKU。"
  type        = string
  default     = "Standard"
}

variable "recovery_vault_storage_mode" {
  description = "Recovery Services Vault 儲存體複寫模式。"
  type        = string
  default     = "LocallyRedundant"

  validation {
    condition     = contains(["LocallyRedundant", "GeoRedundant", "ZoneRedundant"], var.recovery_vault_storage_mode)
    error_message = "recovery_vault_storage_mode 必須為 LocallyRedundant、GeoRedundant 或 ZoneRedundant。"
  }
}

variable "recovery_vault_soft_delete_enabled" {
  description = "是否啟用 Recovery Services Vault Soft Delete。"
  type        = bool
  default     = true
}

############################################
# 服務健康警示
############################################
variable "service_health_locations" {
  description = "服務健康警示監看的 Azure 區域；Global 會保留平台全域事件。"
  type        = list(string)
  default     = ["Global", "Japan East"]
}
