############################################
# outputs.tf
############################################

############################################
# 共用：命名與 TAG
############################################
output "name_prefix_applied" {
  description = "實際套用的名稱前綴。"
  value       = local.prefix
}

output "resource_names" {
  description = "本組態保留資源的最終名稱。"
  value       = local.name
}

output "common_tags" {
  description = "所有資源的共用標籤基準。"
  value       = local.common_tags
}

output "resource_groups" {
  description = "本組態使用的兩個資源群組。"
  value = {
    management = local.mgmt_rg_name
    network    = local.network_rg_name
  }
}

############################################
# 網路與連線
############################################
output "hub_vnet" {
  description = "Hub VNet 與保留名稱子網路。"
  value = {
    id                 = azurerm_virtual_network.hub.id
    name               = azurerm_virtual_network.hub.name
    gateway_subnet_id  = azurerm_subnet.gateway.id
    bastion_subnet_id  = azurerm_subnet.bastion.id
  }
}

output "bastion" {
  description = "Azure Bastion 與其 Public IP。"
  value = {
    id                   = azurerm_bastion_host.hub.id
    name                 = azurerm_bastion_host.hub.name
    public_ip_address    = azurerm_public_ip.bastion.ip_address
    public_ip_address_id = azurerm_public_ip.bastion.id
  }
}

output "vpn" {
  description = "Site-to-Site VPN 資源。"
  value = {
    local_network_gateway_id = azurerm_local_network_gateway.onprem.id
    vpn_gateway_id           = azurerm_virtual_network_gateway.vpn.id
    vpn_gateway_public_ip    = azurerm_public_ip.vpn_gateway.ip_address
    connection_id            = azurerm_virtual_network_gateway_connection.forti.id
  }
}

output "vpn_shared_key" {
  description = "實際使用的 VPN PSK；請用 terraform output -raw vpn_shared_key 安全擷取。"
  value       = local.effective_vpn_shared_key
  sensitive   = true
}

############################################
# 管理與保護
############################################
output "recovery_services_vault" {
  description = "CRM-Backup Recovery Services Vault。"
  value = {
    id   = azurerm_recovery_services_vault.crm_backup.id
    name = azurerm_recovery_services_vault.crm_backup.name
  }
}

output "service_health_alert" {
  description = "Azure 服務健康狀態 Activity Log Alert。"
  value = {
    id   = azurerm_monitor_activity_log_alert.service_health.id
    name = azurerm_monitor_activity_log_alert.service_health.name
  }
}

############################################
# 移除確認
############################################
output "removed_non_workload_resources" {
  description = "本版已從 Terraform 組態移除的 Communication、API Connection 與 Logic Apps。"
  value = [
    "skycs",
    "emailservicesky",
    "AzureManagedDomain",
    "acsemail-2",
    "azurevm",
    "auto_start_vm",
    "auto_stop_vm"
  ]
}
