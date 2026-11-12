output "resource_groups" {
  value = {
    target  = azurerm_resource_group.crm.name
    network = azurerm_resource_group.network.name
  }
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

output "arc_sql_onboarding_target" {
  description = "這是 onboarding 目標，不是假造的 Arc resource ID。實際 ID 由 Agent/Extension 建立。"
  value = {
    machine_name              = var.arc_machine_name
    resource_group           = azurerm_resource_group.crm.name
    location                 = azurerm_resource_group.crm.location
    license_type             = var.arc_sql_license_type
    expected_database_names  = sort(tolist(var.arc_sql_database_names))
    inventory_owner          = "Azure Connected Machine Agent + WindowsAgent.SqlServer"
  }
}
