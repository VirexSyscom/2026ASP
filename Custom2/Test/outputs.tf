output "resource_groups" {
  value = {
    target  = azurerm_resource_group.crm.name
    network = azurerm_resource_group.network.name
  }
}

output "portal_database_rows" {
  description = "在 Spoke-CRM-RG 以『資料庫』篩選時預期看到的 7 筆項目。"
  value = concat(
    [for name in sort(tolist(var.managed_database_names)) : "${name} (${azurerm_mssql_managed_instance.crm.name}/${name})"],
    [for name in sort(tolist(var.arc_sql_database_names)) : "${name} (${azapi_resource.arc_sql_instance.name}/${name})"]
  )
}

output "managed_instance" {
  value = {
    name = azurerm_mssql_managed_instance.crm.name
    id   = azurerm_mssql_managed_instance.crm.id
    fqdn = azurerm_mssql_managed_instance.crm.fqdn
  }
}

output "managed_databases" {
  value = { for name, database in azurerm_mssql_managed_database.database : name => database.id }
}

output "arc_sql_resources" {
  value = {
    machine_id      = azapi_resource.arc_machine.id
    instance_id     = azapi_resource.arc_sql_instance.id
    database_ids    = { for name, database in azapi_resource.arc_sql_database : name => database.id }
  }
}
