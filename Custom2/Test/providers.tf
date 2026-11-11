############################################
# providers.tf
############################################
terraform {
  required_version = ">= 1.9.0, < 2.0.0"

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

# subscription_id 留 null 時，AzureRM Provider 會採用 Azure DevOps
# Service Connection 注入的 ARM_SUBSCRIPTION_ID。
provider "azurerm" {
  features {}

  subscription_id = var.subscription_id
}
