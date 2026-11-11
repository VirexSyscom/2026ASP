data "azurerm_client_config" "current" {}

locals {
  common_tags = merge(var.tags, {
    Location = var.location
  })

  effective_sql_administrator_password = coalesce(
    var.sql_administrator_password,
    random_password.sql_administrator.result
  )

  arc_sql_database_profiles = {
    CRMData = { recovery_mode = "Full", size_mb = 1024, space_available_mb = 512 }
    master  = { recovery_mode = "Simple", size_mb = 8, space_available_mb = 2 }
    model   = { recovery_mode = "Full", size_mb = 16, space_available_mb = 4 }
    msdb    = { recovery_mode = "Simple", size_mb = 32, space_available_mb = 8 }
    tempdb  = { recovery_mode = "Simple", size_mb = 16, space_available_mb = 8 }
  }

  arc_sql_databases = {
    for database_name in var.arc_sql_database_names :
    database_name => local.arc_sql_database_profiles[database_name]
  }

  # 一次性 RSA-2048 公鑰（Base64 DER）；只用於建立 Portal 可見的 Arc Machine 中繼資料。
  arc_machine_client_public_key = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAwNnb65ThyVlL0s/lKDVULK0h+AITiAiOaD2oCXZund09aBoa016bEUO5FU0F8XeYDdVlkzFhLkxrg2WO+0vtzNXCteW5iff1uZdYTkG8YPyO590naLIxaLsXR4EmRwJmMslBr16s92yrDv/FgytIrgtFsZatV2us0+7iT+jUxcImzSkzAJoBWgq98tIUaXXSo4IW/3XtDZhjttX4p5qIHWQqugxoonFRuEQfTIbYWfXJ8Hq5lgqKhvT3zqJLeVsQFqFQdzKgwBrJ1nBfidtlSduWl8gEk/AAzY42psa1SlaIOl1KtOWWDsfc/d2zQNo+ebQUmE9Wv3CnKJqzPDpudQIDAQAB"
}

resource "random_password" "sql_administrator" {
  length           = 24
  special          = true
  override_special = "!@#%"
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}

resource "random_uuid" "arc_machine_vm_id" {}

############################################
# 資源群組
############################################
resource "azurerm_resource_group" "crm" {
  name     = var.crm_resource_group_name
  location = var.location
  tags     = merge(local.common_tags, { Layer = "CRM" })
}

# SQL Managed Instance 的必要支援網路獨立放置，避免污染圖片中的資料庫清單。
resource "azurerm_resource_group" "network" {
  name     = var.network_resource_group_name
  location = var.location
  tags     = merge(local.common_tags, { Layer = "Network" })
}

############################################
# SQL Managed Instance 必要網路
############################################
resource "azurerm_virtual_network" "spoke" {
  name                = var.vnet_name
  location            = azurerm_resource_group.network.location
  resource_group_name = azurerm_resource_group.network.name
  address_space       = var.vnet_address_space
  tags                = local.common_tags
}

resource "azurerm_subnet" "mi" {
  name                 = var.mi_subnet_name
  resource_group_name  = azurerm_resource_group.network.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [var.mi_subnet_prefix]

  delegation {
    name = "managedinstancedelegation"

    service_delegation {
      name = "Microsoft.Sql/managedInstances"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
        "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action",
        "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action",
      ]
    }
  }
}

resource "azurerm_network_security_group" "mi" {
  name                = "nsg-mssqlservermi"
  location            = azurerm_resource_group.network.location
  resource_group_name = azurerm_resource_group.network.name
  tags                = local.common_tags
}

resource "azurerm_network_security_rule" "mi_allow_management_inbound" {
  name                        = "allow_management_inbound"
  priority                    = 106
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_ranges     = ["9000", "9003", "1438", "1440", "1452"]
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.network.name
  network_security_group_name = azurerm_network_security_group.mi.name
}

resource "azurerm_network_security_rule" "mi_allow_subnet_inbound" {
  name                        = "allow_misubnet_inbound"
  priority                    = 200
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = var.mi_subnet_prefix
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.network.name
  network_security_group_name = azurerm_network_security_group.mi.name
}

resource "azurerm_network_security_rule" "mi_allow_health_probe_inbound" {
  name                        = "allow_health_probe_inbound"
  priority                    = 300
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "AzureLoadBalancer"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.network.name
  network_security_group_name = azurerm_network_security_group.mi.name
}

resource "azurerm_network_security_rule" "mi_allow_tds_inbound" {
  name                        = "allow_tds_inbound"
  priority                    = 1000
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "1433"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.network.name
  network_security_group_name = azurerm_network_security_group.mi.name
}

resource "azurerm_network_security_rule" "mi_deny_all_inbound" {
  name                        = "deny_all_inbound"
  priority                    = 4096
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.network.name
  network_security_group_name = azurerm_network_security_group.mi.name
}

resource "azurerm_network_security_rule" "mi_allow_management_outbound" {
  name                        = "allow_management_outbound"
  priority                    = 102
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_ranges     = ["80", "443", "12000"]
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.network.name
  network_security_group_name = azurerm_network_security_group.mi.name
}

resource "azurerm_network_security_rule" "mi_allow_subnet_outbound" {
  name                        = "allow_misubnet_outbound"
  priority                    = 200
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = var.mi_subnet_prefix
  resource_group_name         = azurerm_resource_group.network.name
  network_security_group_name = azurerm_network_security_group.mi.name
}

resource "azurerm_network_security_rule" "mi_deny_all_outbound" {
  name                        = "deny_all_outbound"
  priority                    = 4096
  direction                   = "Outbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.network.name
  network_security_group_name = azurerm_network_security_group.mi.name
}

resource "azurerm_route_table" "mi" {
  name                          = "rt-mssqlservermi"
  location                      = azurerm_resource_group.network.location
  resource_group_name           = azurerm_resource_group.network.name
  bgp_route_propagation_enabled = true
  tags                          = local.common_tags

  lifecycle {
    ignore_changes = [route]
  }
}

resource "azurerm_subnet_network_security_group_association" "mi" {
  subnet_id                 = azurerm_subnet.mi.id
  network_security_group_id = azurerm_network_security_group.mi.id

  depends_on = [
    azurerm_network_security_rule.mi_allow_management_inbound,
    azurerm_network_security_rule.mi_allow_subnet_inbound,
    azurerm_network_security_rule.mi_allow_health_probe_inbound,
    azurerm_network_security_rule.mi_allow_tds_inbound,
    azurerm_network_security_rule.mi_deny_all_inbound,
    azurerm_network_security_rule.mi_allow_management_outbound,
    azurerm_network_security_rule.mi_allow_subnet_outbound,
    azurerm_network_security_rule.mi_deny_all_outbound,
  ]
}

resource "azurerm_subnet_route_table_association" "mi" {
  subnet_id      = azurerm_subnet.mi.id
  route_table_id = azurerm_route_table.mi.id
}

############################################
# 圖片第 1–2 筆：SQL Managed Instance 資料庫
############################################
resource "azurerm_mssql_managed_instance" "crm" {
  name                = var.mi_name
  resource_group_name = azurerm_resource_group.crm.name
  location            = azurerm_resource_group.crm.location
  subnet_id           = azurerm_subnet.mi.id

  administrator_login          = var.sql_administrator_login
  administrator_login_password = local.effective_sql_administrator_password

  license_type                 = var.mi_license_type
  sku_name                     = var.mi_sku_name
  vcores                       = var.mi_vcores
  storage_size_in_gb           = var.mi_storage_size_in_gb
  minimum_tls_version          = "1.2"
  public_data_endpoint_enabled = false
  tags                         = merge(local.common_tags, { ResourceType = "SqlManagedInstance" })

  depends_on = [
    azurerm_subnet_network_security_group_association.mi,
    azurerm_subnet_route_table_association.mi,
  ]
}

resource "azurerm_mssql_managed_database" "database" {
  for_each = var.managed_database_names

  name                = each.key
  managed_instance_id = azurerm_mssql_managed_instance.crm.id
}

############################################
# 圖片第 3–7 筆：Azure Arc SQL Server 資料庫
############################################
resource "azapi_resource" "arc_machine" {
  type      = "Microsoft.HybridCompute/machines@2024-07-10"
  name      = var.arc_machine_name
  location  = azurerm_resource_group.crm.location
  parent_id = azurerm_resource_group.crm.id

  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {
      osType          = "windows"
      vmId            = random_uuid.arc_machine_vm_id.result
      clientPublicKey = local.arc_machine_client_public_key
    }
  }

  tags = merge(local.common_tags, {
    ResourceType = "ArcMachine"
    Purpose      = "SQL-Server-Host"
  })

  schema_validation_enabled = false
}

resource "azapi_resource" "arc_sql_instance" {
  type      = "Microsoft.AzureArcData/sqlServerInstances@2024-01-01"
  name      = var.arc_machine_name
  location  = azurerm_resource_group.crm.location
  parent_id = azurerm_resource_group.crm.id

  body = {
    properties = {
      containerResourceId = azapi_resource.arc_machine.id
      status              = var.arc_sql_status
      edition             = var.arc_sql_edition
      version             = var.arc_sql_version
      instanceName        = var.arc_machine_name
    }
  }

  tags = merge(local.common_tags, { ResourceType = "ArcSqlServerInstance" })

  schema_validation_enabled = false
}

resource "azapi_resource" "arc_sql_database" {
  for_each = local.arc_sql_databases

  type      = "Microsoft.AzureArcData/sqlServerInstances/databases@2024-01-01"
  name      = each.key
  location  = azurerm_resource_group.crm.location
  parent_id = azapi_resource.arc_sql_instance.id

  body = {
    properties = {
      collationName      = "SQL_Latin1_General_CP1_CI_AS"
      compatibilityLevel = 150
      state              = "Online"
      isReadOnly         = false
      recoveryMode       = each.value.recovery_mode
      sizeMB             = each.value.size_mb
      spaceAvailableMB   = each.value.space_available_mb
    }
  }

  tags = merge(local.common_tags, { ResourceType = "ArcSqlServerDatabase" })

  schema_validation_enabled = false
  depends_on                = [azapi_resource.arc_sql_instance]
}
