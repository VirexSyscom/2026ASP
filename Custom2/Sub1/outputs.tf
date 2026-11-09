############################################
# outputs.tf
#   統一格式：共用驗證 → 資源群組 → Spoke 網路
#             → CRM → 遷移工具層（AzureMigrateRG）→ ADF-RG
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

output "crm_tags_applied" {
  description = "CRM 資源群組套用的標籤"
  value       = local.crm_tags
}

output "migrate_tags_applied" {
  description = "AzureMigrateRG 套用的標籤"
  value       = local.migrate_tags
}

output "adf_tags_applied" {
  description = "ADF-RG 套用的標籤"
  value       = local.adf_tags
}

############################################
# 資源群組（四個獨立 RG）
############################################
output "resource_groups" {
  description = "本組態管理的四個資源群組"
  value = {
    network = local.network_rg_name
    crm     = local.crm_rg_name
    migrate = local.migrate_rg_name
    adf     = local.adf_rg_name
  }
}

############################################
# Spoke 網路層
############################################
output "spoke_vnet_id" {
  description = "Spoke VNet 資源 ID"
  value       = azurerm_virtual_network.spoke.id
}

output "subnet_ids" {
  description = "所有子網路資源 ID"
  value = {
    ap = azurerm_subnet.ap.id
    mi = azurerm_subnet.mi.id
    pe = azurerm_subnet.pe.id
  }
}

output "nat_gateway_public_ip" {
  description = "NAT Gateway 對外 IP"
  value       = azurerm_public_ip.nat.ip_address
}

output "network_security_group_ids" {
  description = "Spoke 網路 RG 內的 NSG 資源 ID"
  value = {
    ap   = azurerm_network_security_group.ap.id
    mi   = azurerm_network_security_group.mi.id
    test = azurerm_network_security_group.test.id
  }
}

output "mi_route_table_id" {
  description = "SQL 受控執行個體路由表資源 ID"
  value       = azurerm_route_table.mi.id
}

############################################
# CRM 工作負載層
############################################
output "virtual_machine_names" {
  description = "CRM 虛擬機器名稱"
  value       = [for vm in azurerm_windows_virtual_machine.crm : vm.name]
}

output "virtual_machine_private_ips" {
  description = "CRM 虛擬機器私人 IP"
  value       = { for k, vm in azurerm_windows_virtual_machine.crm : k => vm.private_ip_address }
}

output "load_balancer" {
  description = "CRMAP-LB 內部負載平衡器"
  value = {
    id                  = azurerm_lb.crm.id
    frontend_private_ip = azurerm_lb.crm.frontend_ip_configuration[0].private_ip_address
  }
}

output "compute_gallery" {
  description = "Compute Gallery / 映像定義 / 映像版本"
  value = {
    gallery_name  = azurerm_shared_image_gallery.crm.name
    image_name    = azurerm_shared_image.crm.name
    image_version = try(azurerm_shared_image_version.crm[0].name, null)
    snapshot_id   = try(azurerm_snapshot.crm_image_source[0].id, null)
  }
}

output "vm_user_assigned_identity_id" {
  description = "CRM VM 使用的受控識別 ID"
  value       = azurerm_user_assigned_identity.vm.id
}

output "sql_managed_instance" {
  description = "SQL 受控執行個體與受控資料庫（VirtualCluster 由 Azure 自動產生）"
  value = {
    name        = azurerm_mssql_managed_instance.crm.name
    id          = azurerm_mssql_managed_instance.crm.id
    fqdn        = azurerm_mssql_managed_instance.crm.fqdn
    database_id = azurerm_mssql_managed_database.crm.id
  }
}

output "azure_sql_server" {
  description = "Azure SQL logical server"
  value = {
    id   = azurerm_mssql_server.crm.id
    name = azurerm_mssql_server.crm.name
    fqdn = azurerm_mssql_server.crm.fully_qualified_domain_name
  }
}

output "azure_sql_databases" {
  description = "建立完成的 5 個 Azure SQL Database"
  value = {
    for name, database in azurerm_mssql_database.crm : name => {
      id   = database.id
      name = database.name
    }
  }
}

output "generated_credentials" {
  description = "實際使用的 VM 與 SQL 密碼；輸出標記為 sensitive。請用 terraform output -json generated_credentials 安全擷取。"
  value = {
    vm_admin_password  = local.effective_admin_password
    sql_admin_password = local.effective_sql_administrator_password
  }
  sensitive = true
}

output "asr_seed_disk_id" {
  description = "ASR 種子磁碟資源 ID"
  value       = try(azurerm_managed_disk.asr_seed[0].id, null)
}

output "arc_sql" {
  description = "Azure Arc SQL Server 資源紀錄（azapi 建立，不需真實主機）"
  value = {
    created      = var.create_arc_sql_resources
    machine_id   = try(azapi_resource.arc_machine[0].id, null)
    instance_id  = try(azapi_resource.arc_sql_instance[0].id, null)
    database_ids = { for k, db in azapi_resource.arc_sql_database : k => db.id }
  }
}

output "monitoring" {
  description = "CRM 監控資源"
  value = {
    cpu_alert_id             = azurerm_monitor_metric_alert.cpu.id
    vm_availability_alert_id = azurerm_monitor_metric_alert.vm_availability.id
    nsg_rule_delete_alert_id = azurerm_monitor_activity_log_alert.nsg_rule_delete.id
  }
}

############################################
# 遷移工具層（AzureMigrateRG）
############################################
output "migrate_recovery_vault" {
  description = "復原服務保存庫（對應 discovervmware8406vault）"
  value = {
    name         = azurerm_recovery_services_vault.migrate.name
    id           = azurerm_recovery_services_vault.migrate.id
    sku          = azurerm_recovery_services_vault.migrate.sku
    principal_id = azurerm_recovery_services_vault.migrate.identity[0].principal_id
  }
}

output "migrate_project" {
  description = "Azure Migrate 專案（對應 Migrate-CRM，API 版本 2020-05-01）"
  value = {
    name = azapi_resource.migrate_project.name
    id   = azapi_resource.migrate_project.id
  }
}

output "migrate_key_vault" {
  description = "遷移層 Key Vault（對應 Migrate-CRM5539kv）"
  value = {
    name      = azurerm_key_vault.migrate.name
    id        = azurerm_key_vault.migrate.id
    vault_uri = azurerm_key_vault.migrate.vault_uri
  }
}

output "migrate_storage" {
  description = "遷移記錄儲存體（對應 migratecrmlog）"
  value = {
    account_name = azurerm_storage_account.migrate.name
    account_id   = azurerm_storage_account.migrate.id
  }
}

############################################
# ADF-RG
############################################
output "data_factory" {
  description = "Data Factory（對應 adfsyscom）"
  value = {
    name         = azurerm_data_factory.adf.name
    id           = azurerm_data_factory.adf.id
    principal_id = azurerm_data_factory.adf.identity[0].principal_id
  }
}

output "adf_key_vault" {
  description = "ADF Key Vault（對應 kv-gfs-shir-yxqvj）"
  value = {
    name      = azurerm_key_vault.adf.name
    id        = azurerm_key_vault.adf.id
    vault_uri = azurerm_key_vault.adf.vault_uri
  }
}

output "adf_storage" {
  description = "ADF 儲存體（對應 jgfsshir01）"
  value = {
    account_name = azurerm_storage_account.adf.name
    account_id   = azurerm_storage_account.adf.id
  }
}

output "adf_private_endpoints" {
  description = "ADF-RG 的 Private Endpoint 資源 ID"
  value = {
    adf  = azurerm_private_endpoint.adf.id
    blob = azurerm_private_endpoint.adf_blob.id
    dfs  = azurerm_private_endpoint.adf_dfs.id
    kv   = azurerm_private_endpoint.adf_kv.id
  }
}

output "adf_private_dns_zone_id" {
  description = "privatelink.datafactory.azure.net 私人 DNS 區域資源 ID"
  value       = azurerm_private_dns_zone.datafactory.id
}

output "adf_nsg_id" {
  description = "ADF-NSF 網路安全性群組資源 ID"
  value       = azurerm_network_security_group.adf.id
}
