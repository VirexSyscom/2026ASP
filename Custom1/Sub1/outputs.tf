############################################
# outputs.tf
#   統一格式：共用驗證 → 資源群組 → Spoke 網路
#             → PROD HR → UAT HR → 遷移工具層（AzureMigrateRG）
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

output "network_tags_applied" {
  description = "Spoke 網路資源群組套用的標籤"
  value       = local.network_tags
}

output "hr_tags_applied" {
  description = "PROD HR 資源群組套用的標籤"
  value       = local.hr_tags
}

output "uat_hr_tags_applied" {
  description = "UAT HR 資源群組套用的標籤"
  value       = local.uat_hr_tags
}

output "migrate_tags_applied" {
  description = "AzureMigrateRG 套用的標籤"
  value       = local.migrate_tags
}

############################################
# 資源群組（四個獨立 RG）
############################################
output "resource_groups" {
  description = "本組態管理的四個資源群組"
  value = {
    network = local.network_rg_name
    hr      = local.hr_rg_name
    uat_hr  = local.uat_hr_rg_name
    migrate = local.migrate_rg_name
  }
}

############################################
# Spoke 網路層
############################################
output "spoke_vnet_id" {
  description = "PROD Spoke VNet 資源 ID"
  value       = azurerm_virtual_network.spoke.id
}

output "uat_spoke_vnet_id" {
  description = "UAT Spoke VNet 資源 ID"
  value       = azurerm_virtual_network.uat_spoke.id
}

output "subnet_ids" {
  description = "所有子網路資源 ID"
  value = {
    ap          = azurerm_subnet.ap.id
    db          = azurerm_subnet.db.id
    pe          = azurerm_subnet.pe.id
    bastion     = var.create_bastion_subnet ? azurerm_subnet.bastion[0].id : null
    uat         = azurerm_subnet.uat_workload.id
    uat_pe      = azurerm_subnet.uat_pe.id
    migrate     = var.create_database_migration_service ? azurerm_subnet.migrate[0].id : null
  }
}

output "nat_gateway_public_ip" {
  description = "NAT Gateway 對外 IP"
  value       = azurerm_public_ip.nat.ip_address
}

output "private_dns_zone_ids" {
  description = "Private DNS Zone 資源 ID（PROD / UAT / 遷移層共用）"
  value = {
    blob      = azurerm_private_dns_zone.blob.id
    sql       = azurerm_private_dns_zone.sql.id
    key_vault = azurerm_private_dns_zone.keyvault.id
  }
}

output "bastion_id" {
  description = "Spoke Bastion Host 資源 ID"
  value       = azurerm_bastion_host.spoke.id
}

output "bastion_sku" {
  description = "Spoke 實際部署的 Bastion SKU"
  value       = azurerm_bastion_host.spoke.sku
}

output "bastion_access_model" {
  description = "Spoke Bastion 連線方式說明"
  value       = var.bastion_sku == "Developer" ? "Developer SKU：無公用 IP，僅限 Azure 入口網站連線同一 VNet 內的 VM" : "使用公用 IP 連線"
}

############################################
# PROD HR 工作負載層
############################################
output "virtual_machine_names" {
  description = "PROD HR 虛擬機器名稱"
  value       = [for vm in azurerm_windows_virtual_machine.vm : vm.name]
}

output "load_balancer_public_ip" {
  description = "PROD HR Load Balancer 對外 IP"
  value       = azurerm_public_ip.lb.ip_address
}

output "sql" {
  description = "PROD HR SQL 相關資源"
  value = {
    server_name         = azurerm_mssql_server.hr.name
    server_id           = azurerm_mssql_server.hr.id
    server_fqdn         = azurerm_mssql_server.hr.fully_qualified_domain_name
    database_id         = azurerm_mssql_database.hr.id
    private_endpoint_id = azurerm_private_endpoint.sql.id
    private_endpoint_ip = azurerm_private_endpoint.sql.private_service_connection[0].private_ip_address
  }
}

output "compute_gallery_name" {
  description = "PROD HR Compute Gallery 名稱"
  value       = azurerm_shared_image_gallery.hr.name
}

output "vm_user_assigned_identity_id" {
  description = "PROD HR VM 使用的受控識別 ID"
  value       = azurerm_user_assigned_identity.vm.id
}

output "monitoring" {
  description = "PROD HR 監控資源"
  value = {
    email_action_group_id = azurerm_monitor_action_group.email.id
    vm_action_group_id    = azurerm_monitor_action_group.vm.id
    sql_dtu_alert_id      = azurerm_monitor_metric_alert.sql_dtu.id
  }
}

############################################
# UAT HR 工作負載層
############################################
output "uat_vm" {
  description = "UAT HR 虛擬機器資訊"
  value = {
    id   = azurerm_windows_virtual_machine.uat_vm.id
    name = azurerm_windows_virtual_machine.uat_vm.name
    nic_ids = [
      azurerm_network_interface.uat_vm_primary.id,
      azurerm_network_interface.uat_vm_secondary.id
    ]
    data_disk_id = azurerm_managed_disk.uat_vm_data.id
  }
}

output "uat_sql" {
  description = "UAT HR SQL 相關資源"
  value = {
    server_name         = azurerm_mssql_server.uat_hr.name
    server_id           = azurerm_mssql_server.uat_hr.id
    server_fqdn         = azurerm_mssql_server.uat_hr.fully_qualified_domain_name
    database_id         = azurerm_mssql_database.uat_hr.id
    private_endpoint_id = azurerm_private_endpoint.uat_sql.id
    private_endpoint_ip = azurerm_private_endpoint.uat_sql.private_service_connection[0].private_ip_address
  }
}

output "uat_storage" {
  description = "UAT HR 儲存體相關資源"
  value = {
    account_name        = azurerm_storage_account.uat.name
    account_id          = azurerm_storage_account.uat.id
    private_endpoint_id = azurerm_private_endpoint.uat_storage_blob.id
    system_topic_id     = var.create_uat_eventgrid_system_topic ? azurerm_eventgrid_system_topic.uat_storage[0].id : null
  }
}

output "uat_monitoring" {
  description = "UAT HR 監控資源"
  value = {
    action_group_id          = azurerm_monitor_action_group.uat_vm.id
    vm_availability_alert_id = azurerm_monitor_metric_alert.uat_vm_availability.id
    sql_dtu_alert_id         = azurerm_monitor_metric_alert.uat_sql_dtu.id
  }
}

############################################
# 遷移工具層（AzureMigrateRG）
############################################
output "migrate_recovery_vault" {
  description = "復原服務保存庫（對應 discovervmware4949vault）"
  value = {
    name         = azurerm_recovery_services_vault.migrate.name
    id           = azurerm_recovery_services_vault.migrate.id
    sku          = azurerm_recovery_services_vault.migrate.sku
    principal_id = azurerm_recovery_services_vault.migrate.identity[0].principal_id
  }
}

output "migrate_project" {
  description = "Azure Migrate 專案（對應 Migrate-HR，API 版本 2020-05-01）"
  value = {
    name = azapi_resource.migrate_project.name
    id   = azapi_resource.migrate_project.id
  }
}

output "migrate_key_vault" {
  description = "遷移層 Key Vault（對應 Migrate-HR8786kv）"
  value = {
    name                = azurerm_key_vault.migrate.name
    id                  = azurerm_key_vault.migrate.id
    vault_uri           = azurerm_key_vault.migrate.vault_uri
    private_endpoint_id = try(azurerm_private_endpoint.migrate_kv[0].id, null)
  }
}

output "migrate_storage" {
  description = "遷移記錄儲存體與事件方格（對應 migratelog / migratelog-<guid>）"
  value = {
    account_name        = azurerm_storage_account.migrate.name
    account_id          = azurerm_storage_account.migrate.id
    private_endpoint_id = try(azurerm_private_endpoint.migrate_blob[0].id, null)
    system_topic_id     = var.create_migrate_eventgrid_system_topic ? azurerm_eventgrid_system_topic.migrate_storage[0].id : null
  }
}

output "database_migration_service" {
  description = "Database Migration Service（對應 SQLtoAzureSQL）"
  value = {
    created   = var.create_database_migration_service
    name      = try(azurerm_database_migration_service.sql_to_azure_sql[0].name, null)
    id        = try(azurerm_database_migration_service.sql_to_azure_sql[0].id, null)
    sku       = try(azurerm_database_migration_service.sql_to_azure_sql[0].sku_name, null)
    subnet_id = try(azurerm_subnet.migrate[0].id, null)
  }
}

output "migrate_role_assignment" {
  description = "RSV 對遷移儲存體的角色指派狀態；false 時需由管理員手動指派"
  value = {
    managed_by_terraform = var.create_migrate_role_assignment
    id                   = try(azurerm_role_assignment.vault_to_migrate_storage[0].id, null)
    principal_id         = azurerm_recovery_services_vault.migrate.identity[0].principal_id
    scope                = azurerm_storage_account.migrate.id
    role                 = "Storage Blob Data Contributor"
  }
}
