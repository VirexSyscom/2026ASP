############################################
# outputs.tf
# Hub 基礎設施輸出
############################################

output "resource_groups" {
  description = "Hub 管理與網路資源群組。"
  value = {
    management = {
      name = local.mgmt_rg_name
      id   = local.mgmt_rg_id
    }
    network = {
      name = local.network_rg_name
      id   = local.network_rg_id
    }
  }
}

output "hub_virtual_network" {
  description = "Hub VNet 的名稱、ID 與位址空間。"
  value = {
    name          = azurerm_virtual_network.hub.name
    id            = azurerm_virtual_network.hub.id
    address_space = azurerm_virtual_network.hub.address_space
  }
}

output "hub_subnet_ids" {
  description = "GatewaySubnet 與 AzureBastionSubnet 的資源 ID。"
  value = {
    gateway = azurerm_subnet.gateway.id
    bastion = azurerm_subnet.bastion.id
  }
}

output "bastion" {
  description = "Azure Bastion 與其公用 IP 資訊。"
  value = {
    name              = azurerm_bastion_host.hub.name
    id                = azurerm_bastion_host.hub.id
    public_ip_name    = azurerm_public_ip.bastion.name
    public_ip_address = azurerm_public_ip.bastion.ip_address
  }
}

output "vpn_gateway" {
  description = "VPN Gateway 與公用 IP 資訊。"
  value = {
    name              = azurerm_virtual_network_gateway.vpn.name
    id                = azurerm_virtual_network_gateway.vpn.id
    sku               = var.vpn_gateway_sku
    public_ip_name    = azurerm_public_ip.vpn_gateway.name
    public_ip_address = azurerm_public_ip.vpn_gateway.ip_address
  }
}

output "local_network_gateway" {
  description = "Local Network Gateway 資訊。"
  value = {
    name            = azurerm_local_network_gateway.onprem.name
    id              = azurerm_local_network_gateway.onprem.id
    gateway_address = azurerm_local_network_gateway.onprem.gateway_address
    address_space   = azurerm_local_network_gateway.onprem.address_space
  }
}

output "vpn_connection" {
  description = "Site-to-Site VPN Connection 資訊。"
  value = {
    name = azurerm_virtual_network_gateway_connection.forti.name
    id   = azurerm_virtual_network_gateway_connection.forti.id
  }
}

output "recovery_services_vault" {
  description = "Recovery Services Vault 資訊。"
  value = {
    name = azurerm_recovery_services_vault.crm_backup.name
    id   = azurerm_recovery_services_vault.crm_backup.id
  }
}

output "service_health_alert" {
  description = "Azure Service Health Activity Log Alert 資訊。"
  value = {
    name = azurerm_monitor_activity_log_alert.service_health.name
    id   = azurerm_monitor_activity_log_alert.service_health.id
  }
}

output "vpn_shared_key" {
  description = "VPN 預共用金鑰；若未傳入則由 Terraform 產生。"
  value       = local.effective_vpn_shared_key
  sensitive   = true
}

output "resource_names" {
  description = "套用前綴後的資源名稱。"
  value       = local.name
}

output "common_tags" {
  description = "套用至資源的共用標籤。"
  value       = local.common_tags
}
