############################################
# outputs.tf
############################################
output "resource_groups" {
  description = "本組態建立的資源群組。"
  value = {
    network = local.network_rg_name
    crm     = local.crm_rg_name
  }
}

output "managed_instance" {
  description = "Azure SQL Managed Instance 資訊。"
  value = {
    name         = azurerm_mssql_managed_instance.crmdata.name
    id           = azurerm_mssql_managed_instance.crmdata.id
    fqdn         = azurerm_mssql_managed_instance.crmdata.fqdn
    principal_id = azurerm_mssql_managed_instance.crmdata.identity[0].principal_id
  }
}

output "managed_database" {
  description = "Terraform 管理的 CRMData 使用者資料庫。"
  value = {
    name = azurerm_mssql_managed_database.crmdata.name
    id   = azurerm_mssql_managed_database.crmdata.id
  }
}

output "database_inventory" {
  description = "SQL Managed Instance 內預期的五個資料庫；只有 CRMData 是獨立 ARM/Terraform 資源。"
  value = {
    CRMData = {
      type              = "user"
      terraform_managed = true
    }
    master = {
      type              = "system"
      terraform_managed = false
    }
    model = {
      type              = "system"
      terraform_managed = false
    }
    msdb = {
      type              = "system"
      terraform_managed = false
    }
    tempdb = {
      type              = "system"
      terraform_managed = false
    }
  }
}

output "network" {
  description = "SQL Managed Instance 專用網路資訊。"
  value = {
    vnet_id        = azurerm_virtual_network.spoke.id
    subnet_id      = azurerm_subnet.mi.id
    nsg_id         = azurerm_network_security_group.mi.id
    route_table_id = azurerm_route_table.mi.id
  }
}

output "sql_administrator_login" {
  description = "SQL 管理者登入名稱。"
  value       = var.sql_administrator_login
}

output "sql_administrator_password" {
  description = "實際使用的 SQL 管理者密碼；僅能以 terraform output -raw sql_administrator_password 取得。"
  value       = local.sql_admin_password
  sensitive   = true
}
