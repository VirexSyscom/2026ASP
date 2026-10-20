output "tenant_root_management_group_id" {
  description = "Tenant Root Group Resource ID。"
  value       = data.azurerm_management_group.tenant_root.id
}

output "management_group_ids" {
  description = "建立完成的管理群組 Resource ID。"
  value = {
    alz         = azurerm_management_group.alz.id
    ap_group    = azurerm_management_group.ap_group.id
    infra_group = azurerm_management_group.infra_group.id
  }
}

output "subscription_management_group_mapping" {
  description = "訂閱與目標管理群組的對應。"
  value = {
    connectivity = {
      subscription_id     = data.azurerm_subscription.connectivity.subscription_id
      management_group_id = azurerm_management_group.infra_group.id
    }
    workload = {
      subscription_id     = data.azurerm_subscription.workload.subscription_id
      management_group_id = azurerm_management_group.ap_group.id
    }
    open_ai = {
      subscription_id     = data.azurerm_subscription.open_ai.subscription_id
      management_group_id = data.azurerm_management_group.tenant_root.id
    }
  }
}
