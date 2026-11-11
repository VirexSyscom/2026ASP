############################################
# variables.tf
############################################
variable "subscription_id" {
  description = "Azure 訂閱 ID；預設由 Azure DevOps Service Connection 注入。"
  type        = string
  default     = null
  nullable    = true
}

variable "location" {
  description = "Azure 部署區域。"
  type        = string
  default     = "japaneast"
}

variable "name_prefix" {
  description = "資源名稱前綴；僅可使用小寫英數字，最多 8 碼。"
  type        = string
  default     = "demo"

  validation {
    condition     = can(regex("^[a-z0-9]{0,8}$", var.name_prefix))
    error_message = "name_prefix 只能使用小寫英文字母與數字，且最多 8 碼。"
  }
}

variable "network_resource_group_name" {
  description = "SQL Managed Instance 網路資源群組名稱。"
  type        = string
  default     = "Spoke-Network-RG"
}

variable "create_network_resource_group" {
  description = "true 建立網路資源群組；false 沿用同名既有資源群組。"
  type        = bool
  default     = true
}

variable "crm_resource_group_name" {
  description = "SQL Managed Instance 工作負載資源群組名稱。"
  type        = string
  default     = "Spoke-CRM-RG"
}

variable "create_crm_resource_group" {
  description = "true 建立 CRM 資源群組；false 沿用同名既有資源群組。"
  type        = bool
  default     = true
}

variable "vnet_name" {
  description = "虛擬網路基底名稱。"
  type        = string
  default     = "Spoke-VNET"
}

variable "mi_subnet_name" {
  description = "SQL Managed Instance 專用子網路基底名稱。"
  type        = string
  default     = "MI-Subnet"
}

variable "vnet_address_space" {
  description = "虛擬網路位址空間。"
  type        = list(string)
  default     = ["10.10.0.0/16"]
}

variable "mi_subnet_prefix" {
  description = "SQL Managed Instance 專用子網路；部署後不應任意縮小。"
  type        = string
  default     = "10.10.2.0/24"
}

variable "managed_instance_name_base" {
  description = "SQL Managed Instance DNS 名稱基底；Terraform 會加上前綴與 6 碼亂數以確保全域唯一。"
  type        = string
  default     = "crmdata-mi"

  validation {
    condition = (
      length(var.managed_instance_name_base) >= 1 &&
      length(var.managed_instance_name_base) <= 48 &&
      can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.managed_instance_name_base))
    )
    error_message = "managed_instance_name_base 必須為 1-48 碼小寫英數字或連字號，且首尾不可為連字號。"
  }
}

variable "sql_administrator_login" {
  description = "SQL Managed Instance 管理者登入名稱。"
  type        = string
  default     = "crmadminuser"
}

variable "sql_administrator_password" {
  description = "SQL 管理者密碼。null 時由 Terraform 產生 24 碼密碼並保存於遠端 state；也可用 TF_VAR_sql_administrator_password 覆寫。"
  type        = string
  default     = null
  nullable    = true
  sensitive   = true
}

variable "mi_sku_name" {
  description = "SQL Managed Instance SKU。"
  type        = string
  default     = "GP_Gen5"
}

variable "mi_vcores" {
  description = "SQL Managed Instance vCore 數。"
  type        = number
  default     = 4

  validation {
    condition     = contains([4, 8, 16, 24, 32, 40, 64, 80], var.mi_vcores)
    error_message = "mi_vcores 必須為 4、8、16、24、32、40、64 或 80。"
  }
}

variable "mi_storage_size_in_gb" {
  description = "SQL Managed Instance 儲存體容量（GB，32 的倍數）。"
  type        = number
  default     = 32

  validation {
    condition     = var.mi_storage_size_in_gb >= 32 && var.mi_storage_size_in_gb % 32 == 0
    error_message = "mi_storage_size_in_gb 必須至少 32 GB 且為 32 的倍數。"
  }
}

variable "mi_license_type" {
  description = "LicenseIncluded，或使用 Azure Hybrid Benefit 的 BasePrice。"
  type        = string
  default     = "LicenseIncluded"

  validation {
    condition     = contains(["LicenseIncluded", "BasePrice"], var.mi_license_type)
    error_message = "mi_license_type 必須為 LicenseIncluded 或 BasePrice。"
  }
}

variable "timezone_id" {
  description = "SQL Managed Instance 時區；建立後不可變更。"
  type        = string
  default     = "UTC"
}

variable "crm_database_name" {
  description = "Terraform 管理的使用者資料庫名稱；依需求固定為 CRMData。"
  type        = string
  default     = "CRMData"

  validation {
    condition     = var.crm_database_name == "CRMData"
    error_message = "crm_database_name 必須保持為 CRMData。"
  }
}

variable "tags" {
  description = "套用至支援標籤之資源的標籤。"
  type        = map(string)
  default = {
    Environment = "prod"
    Application = "CRM"
    ManagedBy   = "Terraform"
    DataClass   = "Confidential"
  }
}
