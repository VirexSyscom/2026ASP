############################################
# providers.tf
#   保留支援 Workload 的 Hub 網路、連線、Bastion、備份與服務健康警示。
#   已移除 Communication Services、Email、API Connection 與 Logic Apps，
#   因此不再需要 azapi provider。
############################################
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.10"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }

  backend "azurerm" {}
}

# subscription_id 留 null 時，採用 Azure DevOps Service Connection
# 注入的 ARM_SUBSCRIPTION_ID。
provider "azurerm" {
  features {
    recovery_service {
      vm_backup_stop_protection_and_retain_data_on_destroy = false
      purge_protected_items_from_vault_on_destroy          = false
    }
  }

  subscription_id = var.subscription_id
}
