############################################
# outputs.tf
#   統一格式：共用驗證 → 資源群組 → Hub 網路 → 管理與自動化
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

output "management_tags_applied" {
  description = "Hub-Mgmt-RG 資源套用的標籤"
  value       = local.management_tags
}

output "network_tags_applied" {
  description = "Hub-Network-RG 資源套用的標籤"
  value       = local.network_tags
}

############################################
# 資源群組
############################################
output "resource_groups" {
  description = "本組態管理的兩個資源群組"
  value = {
    management = local.management_rg_name
    network    = local.network_rg_name
  }
}

############################################
# Hub 網路與 VPN
############################################
output "hub_vnet" {
  description = "Hub-VNET 與系統子網路"
  value = {
    id                 = azurerm_virtual_network.hub.id
    gateway_subnet_id  = azurerm_subnet.gateway.id
    bastion_subnet_id  = azurerm_subnet.bastion.id
  }
}

output "public_ip_addresses" {
  description = "Bastion 與 VPN Gateway 公用 IP"
  value = {
    bastion = azurerm_public_ip.bastion.ip_address
    vpn     = azurerm_public_ip.vpn_gateway.ip_address
  }
}

output "vpn" {
  description = "Site-to-Site VPN 主要資源 ID"
  value = {
    virtual_network_gateway_id = azurerm_virtual_network_gateway.vpn.id
    local_network_gateway_id   = azurerm_local_network_gateway.local.id
    connection_id              = azurerm_virtual_network_gateway_connection.fortinet.id
  }
}

############################################
# 管理、備份與自動化
############################################
output "bastion_host_id" {
  description = "Hub-VNET-Bastion 資源 ID"
  value       = azurerm_bastion_host.hub.id
}

output "recovery_services_vault_id" {
  description = "CRM-Backup 復原服務保存庫資源 ID"
  value       = azurerm_recovery_services_vault.crm_backup.id
}

output "communication_services" {
  description = "Communication Service / Email Communication Service / Azure Managed Domain"
  value = {
    communication_service_id = azurerm_communication_service.skycs.id
    email_service_id         = azurerm_email_communication_service.emailservicesky.id
    email_domain_id          = azurerm_email_communication_service_domain.azure_managed.id
  }
}

output "api_connections" {
  description = "兩個 API connection 資源 ID"
  value = {
    acsemail_2 = azapi_resource.acsemail_2.id
    azurevm    = azapi_resource.azurevm.id
  }
}

output "logic_apps" {
  description = "VM 自動開關機 Logic App 工作流程"
  value = {
    auto_start_vm_id = azurerm_logic_app_workflow.auto_start_vm.id
    auto_stop_vm_id  = azurerm_logic_app_workflow.auto_stop_vm.id
  }
}

output "service_health_alert_id" {
  description = "Azure 服務健康狀態警示-Hub 資源 ID"
  value       = azurerm_monitor_activity_log_alert.service_health.id
}

output "generated_vpn_shared_key" {
  description = "實際使用的 VPN 預共用金鑰；請以 terraform output -raw generated_vpn_shared_key 安全擷取。"
  value       = local.effective_vpn_shared_key
  sensitive   = true
}
