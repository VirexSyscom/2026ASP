############################################
# providers.tf
#   - required_version：>= 1.9.0
#   - azurerm 鎖在 4.x：~> 4.10
#       * 不可放寬到 5.x（含破壞性變更）
#   - 本組態僅管理 Hub-Network-RG，不使用 random / azapi，
#     所有資源名稱皆不需要全域唯一後綴
############################################

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.10"
    }
  }

  backend "azurerm" {}
}

# subscription_id 留 null 時，provider 會自動採用 Azure DevOps
# Service Connection 注入的 ARM_SUBSCRIPTION_ID 環境變數。
provider "azurerm" {
  features {}

  subscription_id = var.subscription_id
}
