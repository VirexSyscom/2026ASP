############################################
# main.tf
# Azure SQL Managed Instance + CRMData
############################################
locals {
  prefix         = var.name_prefix == "" ? "" : "${var.name_prefix}-"
  compact_prefix = lower(replace(var.name_prefix, "-", ""))

  managed_instance_name = lower("${local.compact_prefix}${var.managed_instance_name_base}-${random_string.mi_suffix.result}")
  sql_admin_password    = var.sql_administrator_password != null ? var.sql_administrator_password : random_password.sql_administrator[0].result

  # CRMData 是 Terraform 管理的使用者資料庫；其餘四個是 SQL Managed
  # Instance 建立時原生提供的系統資料庫，不能再宣告成 managed database 資源。
  database_inventory = ["CRMData", "master", "model", "msdb", "tempdb"]

  common_tags = merge(var.tags, {
    Location = var.location
    Workload = "CRMData"
  })

  network_rg_name     = var.create_network_resource_group ? azurerm_resource_group.network[0].name : data.azurerm_resource_group.network_existing[0].name
  network_rg_location = var.create_network_resource_group ? azurerm_resource_group.network[0].location : data.azurerm_resource_group.network_existing[0].location
  crm_rg_name         = var.create_crm_resource_group ? azurerm_resource_group.crm[0].name : data.azurerm_resource_group.crm_existing[0].name
  crm_rg_location     = var.create_crm_resource_group ? azurerm_resource_group.crm[0].location : data.azurerm_resource_group.crm_existing[0].location
}

############################################
# 全域唯一名稱與 SQL 管理者密碼
############################################
resource "random_string" "mi_suffix" {
  length  = 6
  upper   = false
  special = false

  keepers = {
    name_base = var.managed_instance_name_base
    prefix    = var.name_prefix
    location  = var.location
  }
}

resource "random_password" "sql_administrator" {
  count = var.sql_administrator_password == null ? 1 : 0

  length           = 24
  special          = true
  override_special = "!@#%_-"
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}

############################################
# 資源群組
############################################
data "azurerm_resource_group" "network_existing" {
  count = var.create_network_resource_group ? 0 : 1
  name  = var.network_resource_group_name
}

resource "azurerm_resource_group" "network" {
  count    = var.create_network_resource_group ? 1 : 0
  name     = var.network_resource_group_name
  location = var.location

  tags = merge(local.common_tags, {
    Layer        = "Network"
    ResourceType = "ResourceGroup"
  })
}

data "azurerm_resource_group" "crm_existing" {
  count = var.create_crm_resource_group ? 0 : 1
  name  = var.crm_resource_group_name
}

resource "azurerm_resource_group" "crm" {
  count    = var.create_crm_resource_group ? 1 : 0
  name     = var.crm_resource_group_name
  location = var.location

  tags = merge(local.common_tags, {
    Layer        = "Database"
    ResourceType = "ResourceGroup"
  })
}

############################################
# SQL Managed Instance 專用網路
############################################
resource "azurerm_virtual_network" "spoke" {
  name                = "${local.prefix}${var.vnet_name}"
  location            = local.network_rg_location
  resource_group_name = local.network_rg_name
  address_space       = var.vnet_address_space

  tags = merge(local.common_tags, {
    Layer        = "Network"
    ResourceType = "VirtualNetwork"
  })
}

resource "azurerm_subnet" "mi" {
  name                 = "${local.prefix}${var.mi_subnet_name}"
  resource_group_name  = local.network_rg_name
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
  name                = "${local.prefix}nsg-crmdata-mi"
  location            = local.network_rg_location
  resource_group_name = local.network_rg_name

  tags = merge(local.common_tags, {
    Layer        = "Network"
    ResourceType = "NetworkSecurityGroup"
  })

  # 子網路委派會以 Network Intent Policy 維護必要規則；避免將服務加入的
  # 規則誤判為 Terraform 漂移。
  lifecycle {
    ignore_changes = [security_rule]
  }
}

resource "azurerm_route_table" "mi" {
  name                          = "${local.prefix}rt-crmdata-mi"
  location                      = local.network_rg_location
  resource_group_name           = local.network_rg_name
  bgp_route_propagation_enabled = true

  tags = merge(local.common_tags, {
    Layer        = "Network"
    ResourceType = "RouteTable"
  })

  # SQL Managed Instance 服務會在專用子網路加入必要路由。
  lifecycle {
    ignore_changes = [route]
  }
}

resource "azurerm_subnet_network_security_group_association" "mi" {
  subnet_id                 = azurerm_subnet.mi.id
  network_security_group_id = azurerm_network_security_group.mi.id
}

resource "azurerm_subnet_route_table_association" "mi" {
  subnet_id      = azurerm_subnet.mi.id
  route_table_id = azurerm_route_table.mi.id

  depends_on = [azurerm_subnet_network_security_group_association.mi]
}

############################################
# SQL Managed Instance 與 CRMData 使用者資料庫
############################################
resource "azurerm_mssql_managed_instance" "crmdata" {
  name                = local.managed_instance_name
  resource_group_name = local.crm_rg_name
  location            = local.crm_rg_location
  subnet_id           = azurerm_subnet.mi.id

  administrator_login          = var.sql_administrator_login
  administrator_login_password = local.sql_admin_password

  license_type                 = var.mi_license_type
  sku_name                     = var.mi_sku_name
  vcores                       = var.mi_vcores
  storage_size_in_gb           = var.mi_storage_size_in_gb
  timezone_id                  = var.timezone_id
  minimum_tls_version          = "1.2"
  public_data_endpoint_enabled = false

  identity {
    type = "SystemAssigned"
  }

  tags = merge(local.common_tags, {
    Layer        = "Database"
    ResourceType = "SqlManagedInstance"
  })

  depends_on = [azurerm_subnet_route_table_association.mi]
}

resource "azurerm_mssql_managed_database" "crmdata" {
  name                = var.crm_database_name
  managed_instance_id = azurerm_mssql_managed_instance.crmdata.id
}
