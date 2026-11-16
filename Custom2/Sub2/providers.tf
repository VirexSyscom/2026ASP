############################################
# providers.tf
# Hub 基礎設施所需 Provider
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

# subscription_id 留為 null 時，AzureRM 會採用 Azure DevOps
# Service Connection 注入的 ARM_SUBSCRIPTION_ID 環境變數。
provider "azurerm" {
  features {
    recovery_service {
      vm_backup_stop_protection_and_retain_data_on_destroy = false
      purge_protected_items_from_vault_on_destroy          = false
    }
  }

  subscription_id = var.subscription_id
}
