variable "subscription_id" {
  description = "Azure 訂閱 ID；Azure DevOps 會以 ARM_SUBSCRIPTION_ID 注入，通常可保持 null。"
  type        = string
  default     = null
  nullable    = true
}

variable "location" {
  description = "Azure 區域。圖片中的位置為 Japan East。"
  type        = string
  default     = "japaneast"
}

variable "crm_resource_group_name" {
  description = "圖片中的目標資源群組。"
  type        = string
  default     = "Spoke-CRM-RG"
}

variable "network_resource_group_name" {
  description = "SQL Managed Instance 必要網路資源所在的輔助資源群組。"
  type        = string
  default     = "Spoke-Network-RG"
}

variable "vnet_name" {
  type    = string
  default = "Spoke-VNET"
}

variable "vnet_address_space" {
  type    = list(string)
  default = ["10.10.0.0/16"]
}

variable "mi_subnet_name" {
  type    = string
  default = "MI-Subnet"
}

variable "mi_subnet_prefix" {
  type    = string
  default = "10.10.2.0/24"
}

variable "mi_name" {
  description = "SQL Managed Instance 名稱，此名稱須全域唯一。"
  type        = string
  default     = "mssqlservermi221u81289"
}

variable "managed_database_names" {
  description = "圖片中的兩個受控資料庫，不得遺漏。"
  type        = set(string)
  default     = ["CRMData", "testCRMData"]

  validation {
    condition = (
      length(var.managed_database_names) == 2 &&
      contains(var.managed_database_names, "CRMData") &&
      contains(var.managed_database_names, "testCRMData")
    )
    error_message = "managed_database_names 必須正好包含 CRMData 與 testCRMData。"
  }
}

variable "sql_administrator_login" {
  type    = string
  default = "sqladminuser"
}

variable "sql_administrator_password" {
  description = "可由 Azure DevOps secret TF_VAR_sql_administrator_password 覆寫；null 時自動產生。"
  type        = string
  default     = null
  nullable    = true
  sensitive   = true
}

variable "mi_sku_name" {
  type    = string
  default = "GP_Gen5"
}

variable "mi_vcores" {
  type    = number
  default = 4
}

variable "mi_storage_size_in_gb" {
  type    = number
  default = 32
}

variable "mi_license_type" {
  type    = string
  default = "LicenseIncluded"
}

variable "arc_machine_name" {
  description = "圖片中 SQL Server 資料庫的父層名稱。"
  type        = string
  default     = "CRM-DB"
}

variable "arc_sql_database_names" {
  description = "圖片中的五個 Azure Arc SQL Server 資料庫，不得遺漏。"
  type        = set(string)
  default     = ["CRMData", "master", "model", "msdb", "tempdb"]

  validation {
    condition = (
      length(var.arc_sql_database_names) == 5 &&
      alltrue([
        for required_name in ["CRMData", "master", "model", "msdb", "tempdb"] :
        contains(var.arc_sql_database_names, required_name)
      ])
    )
    error_message = "arc_sql_database_names 必須正好包含 CRMData、master、model、msdb、tempdb。"
  }
}

variable "arc_sql_edition" {
  type    = string
  default = "Standard"
}

variable "arc_sql_version" {
  type    = string
  default = "SQL Server 2022"
}

variable "arc_sql_status" {
  type    = string
  default = "Connected"
}

variable "tags" {
  description = "套用至可加標籤資源的共同標籤。"
  type        = map(string)
  default = {
    Environment = "demo"
    Workload    = "CRM"
    ManagedBy   = "Terraform"
  }
}
