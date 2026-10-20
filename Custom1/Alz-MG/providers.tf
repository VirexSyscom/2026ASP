provider "azurerm" {
  features {}

  # AzureRM 4.x 需要指定一個有效訂閱供 Provider 初始化。
  # 此值不限制本設定只能管理該訂閱。
  subscription_id = var.provider_subscription_id
  tenant_id       = var.tenant_id
}
