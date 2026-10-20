############################################
# providers.tf
#   - required_version：>= 1.9.0
#   - azurerm 鎖在 4.x：~> 4.10
#       * Bastion Developer SKU 需要 4.x
#       * 不可放寬到 5.x（private_dns_zone_virtual_network_link 有破壞性變更）
#   - random 供 SQL Server / Storage Account / Key Vault 全域唯一名稱使用
#   - azapi：Azure Migrate 專案（Microsoft.Migrate/migrateProjects）
#     在 azurerm 沒有對應資源，需以 azapi 建立
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
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
  }

  backend "azurerm" {}
}

# subscription_id 留 null 時，provider 會自動採用 Azure DevOps
# Service Connection 注入的 ARM_SUBSCRIPTION_ID 環境變數。
provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }

    # azurerm 4.x：一旦宣告 recovery_service 區塊，
    #   vm_backup_stop_protection_and_retain_data_on_destroy
    #   vm_backup_suspend_protection_and_retain_data_on_destroy
    # 必須「擇一」明確指定（ExactlyOneOf），否則 plan 會出現
    # 「Invalid combination of arguments」。兩個都填同樣會報錯。
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
