data "azurerm_client_config" "current" {}

locals {
  common_tags = merge(var.tags, {
    Location = var.location
  })

  effective_sql_administrator_password = coalesce(
    var.sql_administrator_password,
    random_password.sql_administrator.result
  )
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
# Azure Arc SQL Server
############################################
# 本版本刻意不建立 Microsoft.HybridCompute/machines、
# Microsoft.AzureArcData/sqlServerInstances 或 databases。
# 真實 Windows Server 會由 scripts/Install-SqlServerAndOnboardArc.ps1
# 安裝 SQL Server、建立 CRMData，並由 Azure Connected Machine Agent
# 與 WindowsAgent.SqlServer extension 自動探索及建立 Azure Arc inventory。
