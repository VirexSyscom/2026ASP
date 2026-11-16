############################################
# main.tf
#   保留支援 Workload 的 Hub 基礎設施：
#     - Hub VNet / GatewaySubnet / AzureBastionSubnet
#     - Local Network Gateway / VPN Gateway / S2S Connection
#     - Azure Bastion
#     - Recovery Services Vault
#     - Azure Service Health Activity Log Alert
#
#   已移除：
#     - skycs / emailservicesky / AzureManagedDomain
#     - acsemail-2 / azurevm API Connections
#     - auto_start_vm / auto_stop_vm Logic Apps
############################################

data "azurerm_client_config" "current" {}

############################################
# Locals：命名、資源群組與 TAG
############################################
locals {
  prefix = trimspace(var.name_prefix) == "" ? "" : "${trimspace(var.name_prefix)}${var.name_separator}"

  # GatewaySubnet 與 AzureBastionSubnet 是 Azure 保留名稱，不套用前綴。
  name = {
    hub_vnet                = "${local.prefix}Hub-VNET"
    bastion_public_ip       = "${local.prefix}Hub-VNET-IPv4"
    bastion                 = "${local.prefix}Hub-VNET-Bastion"
    recovery_vault          = "${local.prefix}CRM-Backup"
    service_health_alert    = "${local.prefix}Azure 服務健康狀態警示-Hub"
    local_network_gateway   = "${local.prefix}LocalGateway"
    vpn_gateway             = "${local.prefix}VPNGateway"
    vpn_gateway_public_ip   = "${local.prefix}VPNGateway-IPaddress"
    vpn_connection          = "${local.prefix}ToFortiVPN"
    gateway_subnet          = "GatewaySubnet"
    azure_bastion_subnet    = "AzureBastionSubnet"
  }

  common_tags = merge(
    {
      Environment = var.environment
      Owner       = var.owner
      ManagedBy   = "Terraform"
      Location    = var.location
      Prefix      = trimspace(var.name_prefix) == "" ? "none" : trimspace(var.name_prefix)
    },
    trimspace(var.cost_center) == "" ? {} : { CostCenter = var.cost_center },
    var.tags
  )

  mgmt_tags = merge(local.common_tags, { Layer = "Management" }, var.mgmt_tags)
  network_tags = merge(local.common_tags, { Layer = "Network" }, var.network_tags)

  mgmt_rg_name    = var.mgmt_resource_group_name
  network_rg_name = var.network_resource_group_name

  mgmt_rg_id = var.create_mgmt_resource_group ? (
    azurerm_resource_group.mgmt[0].id
    ) : (
    data.azurerm_resource_group.mgmt[0].id
  )

  network_rg_id = var.create_network_resource_group ? (
    azurerm_resource_group.network[0].id
    ) : (
    data.azurerm_resource_group.network[0].id
  )

  effective_vpn_shared_key = var.vpn_shared_key != null ? var.vpn_shared_key : random_password.vpn_shared_key[0].result
}

############################################
# 資源群組：建立或沿用
############################################
resource "azurerm_resource_group" "mgmt" {
  count = var.create_mgmt_resource_group ? 1 : 0

  name     = local.mgmt_rg_name
  location = var.location
  tags     = merge(local.mgmt_tags, { ResourceType = "ResourceGroup" })
}

data "azurerm_resource_group" "mgmt" {
  count = var.create_mgmt_resource_group ? 0 : 1
  name  = local.mgmt_rg_name
}

resource "azurerm_resource_group" "network" {
  count = var.create_network_resource_group ? 1 : 0

  name     = local.network_rg_name
  location = var.location
  tags     = merge(local.network_tags, { ResourceType = "ResourceGroup" })
}

data "azurerm_resource_group" "network" {
  count = var.create_network_resource_group ? 0 : 1
  name  = local.network_rg_name
}

############################################
# VPN PSK：未由安全變數提供時建立亂數
############################################
resource "random_password" "vpn_shared_key" {
  count = var.vpn_shared_key == null ? 1 : 0

  length  = 32
  special = false
}

############################################
# Hub 網路
############################################
resource "azurerm_virtual_network" "hub" {
  name                = local.name.hub_vnet
  location            = var.location
  resource_group_name = local.network_rg_name
  address_space       = var.hub_vnet_address_space

  tags = merge(local.network_tags, {
    ResourceType = "VirtualNetwork"
    Purpose      = "HubConnectivity"
    Workload     = "SharedPlatform"
  })

  depends_on = [
    azurerm_resource_group.network,
    data.azurerm_resource_group.network
  ]
}

resource "azurerm_subnet" "gateway" {
  name                 = local.name.gateway_subnet
  resource_group_name  = local.network_rg_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.gateway_subnet_prefix]
}

resource "azurerm_subnet" "bastion" {
  name                 = local.name.azure_bastion_subnet
  resource_group_name  = local.network_rg_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.bastion_subnet_prefix]
}

############################################
# Hub-Mgmt-RG：Bastion Public IP 與 Bastion
############################################
resource "azurerm_public_ip" "bastion" {
  name                = local.name.bastion_public_ip
  location            = var.location
  resource_group_name = local.mgmt_rg_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = length(var.public_ip_zones) == 0 ? null : var.public_ip_zones

  tags = merge(local.mgmt_tags, {
    ResourceType = "PublicIPAddress"
    Purpose      = "AzureBastion"
    Workload     = "SharedPlatform"
  })

  depends_on = [
    azurerm_resource_group.mgmt,
    data.azurerm_resource_group.mgmt
  ]
}

resource "azurerm_bastion_host" "hub" {
  name                = local.name.bastion
  location            = var.location
  resource_group_name = local.mgmt_rg_name
  sku                 = var.bastion_sku

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.bastion.id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }

  tags = merge(local.mgmt_tags, {
    ResourceType = "Bastion"
    Purpose      = "SecureVMAdministration"
    Workload     = "SharedPlatform"
  })
}

############################################
# Hub-Network-RG：Site-to-Site VPN
############################################
resource "azurerm_public_ip" "vpn_gateway" {
  name                = local.name.vpn_gateway_public_ip
  location            = var.location
  resource_group_name = local.network_rg_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = length(var.public_ip_zones) == 0 ? null : var.public_ip_zones

  tags = merge(local.network_tags, {
    ResourceType = "PublicIPAddress"
    Purpose      = "VPNGateway"
    Workload     = "SharedPlatform"
  })

  depends_on = [
    azurerm_resource_group.network,
    data.azurerm_resource_group.network
  ]
}

resource "azurerm_local_network_gateway" "onprem" {
  name                = local.name.local_network_gateway
  location            = var.location
  resource_group_name = local.network_rg_name
  gateway_address     = var.vpn_peer_public_ip
  address_space       = var.onprem_address_spaces

  tags = merge(local.network_tags, {
    ResourceType = "LocalNetworkGateway"
    Purpose      = "OnPremisesConnectivity"
    Workload     = "SharedPlatform"
  })

  depends_on = [
    azurerm_resource_group.network,
    data.azurerm_resource_group.network
  ]
}

resource "azurerm_virtual_network_gateway" "vpn" {
  name                = local.name.vpn_gateway
  location            = var.location
  resource_group_name = local.network_rg_name

  type          = "Vpn"
  vpn_type      = "RouteBased"
  active_active = var.vpn_active_active
  enable_bgp    = var.vpn_enable_bgp
  sku           = var.vpn_gateway_sku
  generation    = var.vpn_gateway_generation

  ip_configuration {
    name                          = "vnetGatewayConfig"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vpn_gateway.id
    subnet_id                     = azurerm_subnet.gateway.id
  }

  tags = merge(local.network_tags, {
    ResourceType = "VirtualNetworkGateway"
    Purpose      = "SiteToSiteVPN"
    Workload     = "SharedPlatform"
  })
}

resource "azurerm_virtual_network_gateway_connection" "forti" {
  name                = local.name.vpn_connection
  location            = var.location
  resource_group_name = local.network_rg_name

  type                       = "IPsec"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.vpn.id
  local_network_gateway_id   = azurerm_local_network_gateway.onprem.id
  shared_key                 = local.effective_vpn_shared_key

  tags = merge(local.network_tags, {
    ResourceType = "VPNConnection"
    Purpose      = "FortiGateSiteToSiteVPN"
    Workload     = "SharedPlatform"
  })
}

############################################
# Hub-Mgmt-RG：備份與服務健康狀態
############################################
resource "azurerm_recovery_services_vault" "crm_backup" {
  name                = local.name.recovery_vault
  location            = var.location
  resource_group_name = local.mgmt_rg_name
  sku                 = var.recovery_vault_sku
  storage_mode_type   = var.recovery_vault_storage_mode
  soft_delete_enabled = var.recovery_vault_soft_delete_enabled

  tags = merge(local.mgmt_tags, {
    ResourceType = "RecoveryServicesVault"
    Purpose      = "WorkloadBackup"
    Workload     = "CRM"
  })

  depends_on = [
    azurerm_resource_group.mgmt,
    data.azurerm_resource_group.mgmt
  ]
}

resource "azurerm_monitor_activity_log_alert" "service_health" {
  name                = local.name.service_health_alert
  resource_group_name = local.mgmt_rg_name
  scopes              = ["/subscriptions/${data.azurerm_client_config.current.subscription_id}"]
  description         = "Azure 服務健康狀態事件警示；通知 Action Group 可依實際需求另行加入。"
  enabled             = true

  criteria {
    category = "ServiceHealth"

    service_health {
      locations = var.service_health_locations
    }
  }

  tags = merge(local.mgmt_tags, {
    ResourceType = "ActivityLogAlert"
    Purpose      = "ServiceHealthMonitoring"
    Workload     = "SharedPlatform"
  })

  depends_on = [
    azurerm_resource_group.mgmt,
    data.azurerm_resource_group.mgmt
  ]
}
