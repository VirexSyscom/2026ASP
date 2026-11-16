############################################
# providers.tf
#   - Terraform >= 1.9.0
#   - azurerm 鎖定 4.x：~> 4.10
#   - azapi 建立 Microsoft.Web/connections（API connection）
#   - random 產生 VPN 預共用金鑰（未由 TF_VAR_vpn_shared_key 覆寫時）
############################################
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.10"
    }

    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }

  backend "azurerm" {}
}

# subscription_id 留 null 時，provider 會自動採用 Azure DevOps
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

provider "azapi" {
  subscription_id = var.subscription_id
}
