############################################
# outputs.tf
#   統一格式：共用驗證 → 資源群組 → Hub 網路 → 監控
############################################

############################################
# 共用：命名與標籤驗證
############################################

output "name_prefix_applied" {
  description = "實際套用的前綴字串"
  value       = local.prefix
}

output "resource_names" {
  description = "所有資源的最終名稱，可用於驗證前綴是否正確套用"
  value       = local.name
}

output "common_tags" {
  description = "套用到所有資源的共用標籤基準"
  value       = local.common_tags
}

output "hub_tags_applied" {
  description = "Hub 網路資源群組套用的標籤"
  value       = local.hub_tags
}

############################################
# 資源群組
############################################

output "resource_groups" {
  description = "本組態管理的資源群組"
  value = {
    hub = local.hub_rg_name
  }
}

############################################
# Hub 網路層
############################################

output "hub_vnet" {
  description = "Hub VNet 資訊"
  value = {
    id   = azurerm_virtual_network.hub.id
    name = azurerm_virtual_network.hub.name
  }
}

output "gateway_subnet_id" {
  description = "GatewaySubnet 資源 ID"
  value       = var.create_vpn_gateway ? azurerm_subnet.gateway[0].id : null
}

output "hub_bastion_public_ip" {
  description = "Hub Bastion 公用 IP 資訊（hub-vnet-bastion-IPaddress）"
  value = {
    id         = try(azurerm_public_ip.hub_bastion[0].id, null)
    name       = try(azurerm_public_ip.hub_bastion[0].name, null)
    ip_address = try(azurerm_public_ip.hub_bastion[0].ip_address, null)
  }
}

output "vpn_gateway" {
  description = "VPN Gateway 與 Local Network Gateway 資訊"
  value = {
    id                       = try(azurerm_virtual_network_gateway.vpn[0].id, null)
    public_ip                = try(azurerm_public_ip.vpn_gateway[0].ip_address, null)
    sku                      = try(azurerm_virtual_network_gateway.vpn[0].sku, null)
    bgp_enabled              = try(azurerm_virtual_network_gateway.vpn[0].bgp_enabled, null)
    local_network_gateway_id = try(azurerm_local_network_gateway.fortigate[0].id, null)
  }
}

output "vpn_connection" {
  description = "Site-to-Site VPN Connection 資訊（ToFortiVPN）"
  value = {
    created = var.create_vpn_gateway && var.create_vpn_connection
    id      = try(azurerm_virtual_network_gateway_connection.fortigate[0].id, null)
    name    = try(azurerm_virtual_network_gateway_connection.fortigate[0].name, null)
  }
}

############################################
# 監控
############################################

output "log_analytics_workspace" {
  description = "Entra-Risky-SignIn 使用的 Log Analytics 工作區"
  value = {
    created = var.create_risky_signin_alert && var.create_log_analytics_workspace
    id      = var.create_risky_signin_alert ? local.alert_workspace_id : null
    name    = try(azurerm_log_analytics_workspace.hub[0].name, null)
  }
}

output "entra_risky_signin_alert" {
  description = "Entra-Risky-SignIn 記錄搜尋警示規則"
  value = {
    created = var.create_risky_signin_alert
    id      = try(azurerm_monitor_scheduled_query_rules_alert_v2.risky_signin[0].id, null)
    name    = try(azurerm_monitor_scheduled_query_rules_alert_v2.risky_signin[0].name, null)
  }
}
