variable "tenant_id" {
  type        = string
  description = "Microsoft Entra tenant ID，也是 Tenant Root Group 的管理群組 ID。"

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.tenant_id))
    error_message = "tenant_id 必須是有效的 GUID。"
  }
}

variable "provider_subscription_id" {
  type        = string
  description = "供 AzureRM Provider 初始化使用的 Subscription ID，建議填 Connectivity subscription ID。"

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.provider_subscription_id))
    error_message = "provider_subscription_id 必須是有效的 GUID。"
  }
}

variable "connectivity_subscription_id" {
  type        = string
  description = "Connectivity subscription 的 Subscription ID。"

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.connectivity_subscription_id))
    error_message = "connectivity_subscription_id 必須是有效的 GUID。"
  }
}

variable "workload_subscription_id" {
  type        = string
  description = "Workload subscription 的 Subscription ID。"

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.workload_subscription_id))
    error_message = "workload_subscription_id 必須是有效的 GUID。"
  }
}

variable "open_ai_subscription_id" {
  type        = string
  description = "Open AI-02 Azure subscription 的 Subscription ID，將直接放在 Tenant Root Group。"

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.open_ai_subscription_id))
    error_message = "open_ai_subscription_id 必須是有效的 GUID。"
  }
}

variable "management_group_names" {
  type = object({
    alz         = string
    ap_group    = string
    infra_group = string
  })

  description = "管理群組的唯一 ID。建立後不建議任意變更。"

  default = {
    alz         = "alz"
    ap_group    = "apgroup"
    infra_group = "infragroup"
  }
}

variable "management_group_display_names" {
  type = object({
    alz         = string
    ap_group    = string
    infra_group = string
  })

  description = "Azure Portal 顯示的管理群組名稱。"

  default = {
    alz         = "ALZ"
    ap_group    = "APGroup"
    infra_group = "InfraGroup"
  }
}
