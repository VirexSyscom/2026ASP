# 取得 Tenant Root Group。
data "azurerm_management_group" "tenant_root" {
  name = var.tenant_id
}

# 以資料來源讀取三個既有訂閱，並取得完整 Azure Resource ID。
data "azurerm_subscription" "connectivity" {
  subscription_id = var.connectivity_subscription_id
}

data "azurerm_subscription" "workload" {
  subscription_id = var.workload_subscription_id
}

data "azurerm_subscription" "open_ai" {
  subscription_id = var.open_ai_subscription_id
}

# Tenant Root Group
# ├── ALZ
# │   ├── APGroup
# │   │   └── Workload subscription
# │   └── InfraGroup
# │       └── Connectivity subscription
# └── Open AI-02 Azure subscription

resource "azurerm_management_group" "alz" {
  name                       = var.management_group_names.alz
  display_name               = var.management_group_display_names.alz
  parent_management_group_id = data.azurerm_management_group.tenant_root.id
}

resource "azurerm_management_group" "ap_group" {
  name                       = var.management_group_names.ap_group
  display_name               = var.management_group_display_names.ap_group
  parent_management_group_id = azurerm_management_group.alz.id
}

resource "azurerm_management_group" "infra_group" {
  name                       = var.management_group_names.infra_group
  display_name               = var.management_group_display_names.infra_group
  parent_management_group_id = azurerm_management_group.alz.id
}

resource "azurerm_management_group_subscription_association" "workload" {
  management_group_id = azurerm_management_group.ap_group.id
  subscription_id     = data.azurerm_subscription.workload.id
}

resource "azurerm_management_group_subscription_association" "connectivity" {
  management_group_id = azurerm_management_group.infra_group.id
  subscription_id     = data.azurerm_subscription.connectivity.id
}

# 多出來的訂閱直接保留／關聯在 Tenant Root Group。
resource "azurerm_management_group_subscription_association" "open_ai" {
  management_group_id = data.azurerm_management_group.tenant_root.id
  subscription_id     = data.azurerm_subscription.open_ai.id
}
