############################################
# variables.tf
#   Hub-Network-RG 獨立版本
#   與其他資源群組（Spoke / HR / UAT / Migrate）完全無關：
#     - 不含 Spoke VNet、Peering、Private DNS Zone Link
#     - 不引用任何其他 RG 的資源或 Action Group
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
# 命名前綴
############################################

variable "name_prefix" {
  description = "所有資源名稱的前綴詞，例如 demo、hr、corp。留空則不加前綴（名稱與入口網站現況相同）。資源群組名稱不套用前綴。"
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

############################################
# 資源群組（名稱不套用前綴）
############################################

variable "hub_resource_group_name" {
  description = "Hub 網路資源群組名稱（VNet / VPN Gateway / Local Gateway / VPN Connection / 公用 IP / 警示規則皆置於此）"
  type        = string
  default     = "Hub-Network-RG"
}

variable "create_hub_resource_group" {
  description = "true = 由本組態建立 Hub RG；false = 沿用既有 RG"
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

variable "hub_tags" {
  description = "僅套用於 Hub 網路資源群組資源的額外標籤"
  type        = map(string)
  default     = {}
}

############################################
# 網路位址 - Hub
############################################

variable "hub_vnet_address_space" {
  description = "Hub VNet 位址空間"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "gateway_subnet_prefixes" {
  description = "Hub GatewaySubnet CIDR，建議 /27 以上"
  type        = list(string)
  default     = ["10.0.1.0/27"]
}

############################################
# Bastion 公用 IP（對應 hub-vnet-bastion-IPaddress）
############################################

variable "create_hub_bastion_public_ip" {
  description = "是否建立 Hub Bastion 用的 Standard 靜態公用 IP（資源群組內僅有公用 IP，未含 Bastion Host）"
  type        = bool
  default     = true
}

############################################
# VPN Gateway / Site-to-Site（Hub）
############################################

variable "create_vpn_gateway" {
  description = "是否建立 VPN Gateway（含 GatewaySubnet、公用 IP 與 Local Network Gateway）。建立時間約 30-45 分鐘。"
  type        = bool
  default     = true
}

variable "vpn_gateway_sku" {
  description = "Azure VPN Gateway SKU"
  type        = string
  default     = "VpnGw2AZ"

  validation {
    condition = contains([
      "Basic",
      "VpnGw1", "VpnGw2", "VpnGw3", "VpnGw4", "VpnGw5",
      "VpnGw1AZ", "VpnGw2AZ", "VpnGw3AZ", "VpnGw4AZ", "VpnGw5AZ"
    ], var.vpn_gateway_sku)
    error_message = "請指定有效的 VPN Gateway SKU。"
  }
}

variable "vpn_gateway_public_ip_zones" {
  description = "VPN Gateway Standard Public IP 的 Availability Zones"
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "enable_bgp" {
  description = "是否於 Azure VPN Gateway 與 Connection 啟用 BGP（對應資源參數已改用 bgp_enabled）"
  type        = bool
  default     = false
}

variable "onprem_vpn_public_ip" {
  description = "地端 FortiGate 的公用 IP 位址"
  type        = string
  default     = "203.0.113.10"

  validation {
    condition     = can(cidrhost("${var.onprem_vpn_public_ip}/32", 0))
    error_message = "onprem_vpn_public_ip 必須是有效的 IPv4 位址。"
  }
}

variable "onprem_address_spaces" {
  description = "FortiGate 後方的地端網段"
  type        = list(string)
  default     = ["192.168.0.0/16"]
}

variable "create_vpn_connection" {
  description = "是否建立 Site-to-Site VPN Connection（ToFortiVPN）"
  type        = bool
  default     = false
}

variable "vpn_shared_key" {
  description = "IPsec Pre-Shared Key。只有建立 VPN Connection 時才需要。"
  type        = string
  sensitive   = true
  default     = null

  validation {
    condition = (
      var.create_vpn_connection == false ||
      (var.vpn_shared_key != null && length(trimspace(var.vpn_shared_key)) > 0)
    )
    error_message = "create_vpn_connection 為 true 時，必須提供非空白的 vpn_shared_key。"
  }
}

############################################
# 監控：Entra-Risky-SignIn（記錄搜尋警示規則）
#   警示規則需要一個 Log Analytics 工作區當資料來源。
#   為了讓 Hub-Network-RG 完全獨立，預設在同一個 RG 內建立專屬工作區；
#   若改用既有工作區，請將 create_log_analytics_workspace 設為 false
#   並填入 log_analytics_workspace_id（僅為字串，不會產生 Terraform 相依）。
############################################

variable "create_risky_signin_alert" {
  description = "是否建立 Entra-Risky-SignIn 記錄搜尋警示規則"
  type        = bool
  default     = true
}

variable "create_log_analytics_workspace" {
  description = "true = 在 Hub RG 內建立專屬 Log Analytics 工作區；false = 使用 log_analytics_workspace_id 指定的既有工作區"
  type        = bool
  default     = true
}

variable "log_analytics_workspace_id" {
  description = "既有 Log Analytics 工作區資源 ID。僅在 create_log_analytics_workspace = false 時使用。"
  type        = string
  default     = ""
}

variable "log_analytics_retention_days" {
  description = "專屬 Log Analytics 工作區的資料保留天數"
  type        = number
  default     = 30
}

variable "alert_action_group_id" {
  description = "警示要通知的 Action Group 資源 ID；留空則警示規則不綁定任何 Action Group（僅在入口網站顯示觸發記錄）"
  type        = string
  default     = ""
}

variable "risky_signin_alert_severity" {
  description = "Entra-Risky-SignIn 警示嚴重性（0 = Critical ~ 4 = Verbose）"
  type        = number
  default     = 1

  validation {
    condition     = var.risky_signin_alert_severity >= 0 && var.risky_signin_alert_severity <= 4
    error_message = "risky_signin_alert_severity 必須介於 0 到 4。"
  }
}

variable "risky_signin_alert_frequency" {
  description = "警示規則評估頻率（ISO 8601，例如 PT5M）"
  type        = string
  default     = "PT5M"
}

variable "risky_signin_alert_window" {
  description = "警示規則查詢時間範圍（ISO 8601，例如 PT5M）"
  type        = string
  default     = "PT5M"
}

variable "risky_signin_alert_query" {
  description = "Entra-Risky-SignIn 使用的 KQL 查詢（預設偵測中 / 高風險的登入）"
  type        = string
  default     = <<-KQL
    SigninLogs
    | where RiskLevelDuringSignIn in~ ("medium", "high")
    | project TimeGenerated, UserPrincipalName, IPAddress, AppDisplayName, RiskLevelDuringSignIn, RiskState
  KQL
}
