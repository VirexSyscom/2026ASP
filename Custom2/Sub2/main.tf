############################################
# main.tf
#   Hub 網路 + Site-to-Site VPN
#   + 管理、監控、備份、Bastion、自動化與 Communication Services
#
#   統一格式：
#     1. 可自訂名稱一律經由 local.name 統一表，套用 local.prefix 前綴
#     2. 標籤一律以 merge(local.<層>_tags, { ResourceType = ... }) 產生
#     3. Hub-Mgmt-RG / Hub-Network-RG 名稱不套用前綴，但標籤一律套用
#     4. 兩個 RG 皆支援 create_<層>_resource_group 切換新建 / 沿用既有
#     5. GatewaySubnet / AzureBastionSubnet / AzureManagedDomain 為 Azure 保留名稱，
#        不套用前綴
#
#   圖片逐列列出的 16 個頂層資源均已納入；另建立 Bastion 與 VPN Gateway
#   必要的兩個 VNet 子網路。圖片未提供 API connection 驗證參數與 Logic App
#   definition，故以前置變數與空白工作流程骨架保留後續設定點。
############################################

locals {
  # 前綴：留空時不加分隔符號，例如 name_prefix = "demo" -> "demo-"
  prefix = var.name_prefix == "" ? "" : "${var.name_prefix}${var.name_separator}"

  # ---------- 統一命名表 ----------
  name = {
    # ===== Hub 網路層 =====
    hub_vnet             = "${local.prefix}Hub-VNET"
    gateway_subnet       = "GatewaySubnet"
    bastion_subnet       = "AzureBastionSubnet"
    local_gateway        = "${local.prefix}LocalGateway"
    vpn_connection       = "${local.prefix}ToFortiVPN"
    vpn_gateway          = "${local.prefix}VPNGateway"
    vpn_gateway_pip      = "${local.prefix}VPNGateway-IPaddress"

    # ===== 管理與自動化層 =====
    bastion_pip          = "${local.prefix}Hub-VNET-IPv4"
    service_health_alert = "${local.prefix}Azure 服務健康狀態警示-Hub"
    recovery_vault       = "${local.prefix}CRM-Backup"
    api_connection_acs   = "${local.prefix}acsemail-2"
    api_connection_vm    = "${local.prefix}azurevm"
    bastion              = "${local.prefix}Hub-VNET-Bastion"
    communication        = "${local.prefix}skycs"
    email_communication  = "${local.prefix}emailservicesky"
    email_domain         = "AzureManagedDomain"
    logic_auto_start     = "${local.prefix}auto_start_vm"
    logic_auto_stop      = "${local.prefix}auto_stop_vm"
  }

  # ---------- 統一標籤 ----------
  common_tags = merge(
    {
      Environment = var.environment
      Owner       = var.owner
      ManagedBy   = "Terraform"
      Location    = var.location
      Prefix      = var.name_prefix
    },
    var.cost_center == "" ? {} : { CostCenter = var.cost_center },
    var.tags
  )

  management_tags = merge(
    local.common_tags,
    {
      Layer    = "Management"
      Workload = "Hub-Shared-Services"
    },
    var.management_tags
  )

  network_tags = merge(
    local.common_tags,
    {
      Layer = "Network"
      Tier  = "Hub"
    },
    var.network_tags
  )

  # ---------- 資源群組解析 ----------
  management_rg_name     = var.create_management_resource_group ? azurerm_resource_group.management[0].name : data.azurerm_resource_group.management_existing[0].name
  management_rg_location = var.create_management_resource_group ? azurerm_resource_group.management[0].location : data.azurerm_resource_group.management_existing[0].location
  management_rg_id       = var.create_management_resource_group ? azurerm_resource_group.management[0].id : data.azurerm_resource_group.management_existing[0].id

  network_rg_name     = var.create_network_resource_group ? azurerm_resource_group.network[0].name : data.azurerm_resource_group.network_existing[0].name
  network_rg_location = var.create_network_resource_group ? azurerm_resource_group.network[0].location : data.azurerm_resource_group.network_existing[0].location
  network_rg_id       = var.create_network_resource_group ? azurerm_resource_group.network[0].id : data.azurerm_resource_group.network_existing[0].id

  subscription_scope   = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  managed_api_base_id  = "${local.subscription_scope}/providers/Microsoft.Web/locations/${var.location}/managedApis"
  effective_vpn_shared_key = var.vpn_shared_key != null ? var.vpn_shared_key : random_password.vpn_shared_key[0].result
}

data "azurerm_client_config" "current" {}

############################################
# VPN 預共用金鑰
############################################
resource "random_password" "vpn_shared_key" {
  count = var.vpn_shared_key == null ? 1 : 0

  length           = 32
  special          = true
  override_special = "!@#%_-"
  min_upper        = 4
  min_lower        = 4
  min_numeric      = 4
  min_special      = 4
}

############################################
# 資源群組（名稱不套用前綴，但一律套用統一標籤）
############################################
data "azurerm_resource_group" "management_existing" {
  count = var.create_management_resource_group ? 0 : 1
  name  = var.management_resource_group_name
}

resource "azurerm_resource_group" "management" {
  count    = var.create_management_resource_group ? 1 : 0
  name     = var.management_resource_group_name
  location = var.location

  tags = merge(local.management_tags, {
    ResourceType = "ResourceGroup"
  })
}

data "azurerm_resource_group" "network_existing" {
  count = var.create_network_resource_group ? 0 : 1
  name  = var.network_resource_group_name
}

resource "azurerm_resource_group" "network" {
  count    = var.create_network_resource_group ? 1 : 0
  name     = var.network_resource_group_name
  location = var.location

  tags = merge(local.network_tags, {
    ResourceType = "ResourceGroup"
  })
}

############################################
# 【Hub 網路】Virtual Network - Hub-VNET
############################################
resource "azurerm_virtual_network" "hub" {
  name                = local.name.hub_vnet
  location            = local.network_rg_location
  resource_group_name = local.network_rg_name
  address_space       = var.hub_vnet_address_space

  tags = merge(local.network_tags, {
    ResourceType = "VirtualNetwork"
    Purpose      = "Hub-Connectivity"
  })
}

# Virtual Network Gateway 必要的保留子網路。
resource "azurerm_subnet" "gateway" {
  name                 = local.name.gateway_subnet
  resource_group_name  = local.network_rg_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.gateway_subnet_prefix]
}

# Azure Bastion 必要的保留子網路；Bastion 本體可置於不同資源群組。
resource "azurerm_subnet" "bastion" {
  name                 = local.name.bastion_subnet
  resource_group_name  = local.network_rg_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.bastion_subnet_prefix]
}

############################################
# 【Hub 網路】Public IP - VPNGateway-IPaddress
############################################
resource "azurerm_public_ip" "vpn_gateway" {
  name                = local.name.vpn_gateway_pip
  location            = local.network_rg_location
  resource_group_name = local.network_rg_name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = merge(local.network_tags, {
    ResourceType = "PublicIP"
    Purpose      = "VPN-Gateway"
  })
}

############################################
# 【Hub 網路】Virtual Network Gateway - VPNGateway
############################################
resource "azurerm_virtual_network_gateway" "vpn" {
  name                = local.name.vpn_gateway
  location            = local.network_rg_location
  resource_group_name = local.network_rg_name

  type          = "Vpn"
  vpn_type      = "RouteBased"
  active_active = false
  enable_bgp    = false
  sku           = var.vpn_gateway_sku

  ip_configuration {
    name                          = "vnetGatewayConfig"
    public_ip_address_id          = azurerm_public_ip.vpn_gateway.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway.id
  }

  tags = merge(local.network_tags, {
    ResourceType = "VirtualNetworkGateway"
    Purpose      = "Site-to-Site-VPN"
  })
}

############################################
# 【Hub 網路】Local Network Gateway - LocalGateway
############################################
resource "azurerm_local_network_gateway" "local" {
  name                = local.name.local_gateway
  location            = local.network_rg_location
  resource_group_name = local.network_rg_name
  gateway_address     = var.vpn_peer_public_ip
  address_space       = var.onprem_address_spaces

  tags = merge(local.network_tags, {
    ResourceType = "LocalNetworkGateway"
    Purpose      = "OnPremises-Network"
  })
}

############################################
# 【Hub 網路】Connection - ToFortiVPN
############################################
resource "azurerm_virtual_network_gateway_connection" "fortinet" {
  name                = local.name.vpn_connection
  location            = local.network_rg_location
  resource_group_name = local.network_rg_name

  type                       = "IPsec"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.vpn.id
  local_network_gateway_id   = azurerm_local_network_gateway.local.id
  shared_key                 = local.effective_vpn_shared_key

  tags = merge(local.network_tags, {
    ResourceType = "VirtualNetworkGatewayConnection"
    Purpose      = "Fortinet-Site-to-Site-VPN"
  })
}

############################################
# 【管理】Public IP - Hub-VNET-IPv4
############################################
resource "azurerm_public_ip" "bastion" {
  name                = local.name.bastion_pip
  location            = local.management_rg_location
  resource_group_name = local.management_rg_name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = merge(local.management_tags, {
    ResourceType = "PublicIP"
    Purpose      = "Azure-Bastion"
  })
}

############################################
# 【管理】Azure Bastion - Hub-VNET-Bastion
############################################
resource "azurerm_bastion_host" "hub" {
  name                = local.name.bastion
  location            = local.management_rg_location
  resource_group_name = local.management_rg_name
  sku                 = var.bastion_sku

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.bastion.id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }

  tags = merge(local.management_tags, {
    ResourceType = "BastionHost"
    Purpose      = "Secure-Administration"
  })
}

############################################
# 【管理】Recovery Services Vault - CRM-Backup
############################################
resource "azurerm_recovery_services_vault" "crm_backup" {
  name                = local.name.recovery_vault
  location            = local.management_rg_location
  resource_group_name = local.management_rg_name
  sku                 = var.recovery_vault_sku
  storage_mode_type   = var.recovery_vault_storage_mode
  soft_delete_enabled = var.recovery_vault_soft_delete_enabled

  tags = merge(local.management_tags, {
    ResourceType = "RecoveryServicesVault"
    Workload     = "CRM"
    Purpose      = "Backup"
  })
}

############################################
# 【管理】Communication Service - skycs
############################################
resource "azurerm_communication_service" "skycs" {
  name                = local.name.communication
  resource_group_name = local.management_rg_name
  data_location       = var.communication_data_location

  tags = merge(local.management_tags, {
    ResourceType = "CommunicationService"
    Purpose      = "Application-Communication"
  })
}

############################################
# 【管理】Email Communication Service - emailservicesky
############################################
resource "azurerm_email_communication_service" "emailservicesky" {
  name                = local.name.email_communication
  resource_group_name = local.management_rg_name
  data_location       = var.communication_data_location

  tags = merge(local.management_tags, {
    ResourceType = "EmailCommunicationService"
    Purpose      = "Application-Email"
  })
}

# AzureManagedDomain 是 Azure Email Communication Services 的保留名稱，不加前綴。
resource "azurerm_email_communication_service_domain" "azure_managed" {
  name             = local.name.email_domain
  email_service_id = azurerm_email_communication_service.emailservicesky.id
  domain_management = "AzureManaged"

  tags = merge(local.management_tags, {
    ResourceType = "EmailCommunicationServiceDomain"
    Purpose      = "Azure-Managed-Email-Domain"
  })
}

############################################
# 【管理】API connections - acsemail-2 / azurevm
#   圖片未提供驗證參數。空 map 可建立連線資源骨架；若 Managed API
#   要求 connectionParameters，請以 TF_VAR_*_connection_parameter_values 補入。
############################################
resource "azapi_resource" "acsemail_2" {
  type      = "Microsoft.Web/connections@2016-06-01"
  name      = local.name.api_connection_acs
  parent_id = local.management_rg_id
  location  = local.management_rg_location
  tags      = merge(local.management_tags, { ResourceType = "ApiConnection", Connector = "ACS-Email" })

  body = {
    properties = merge(
      {
        displayName = local.name.api_connection_acs
        api = {
          id = "${local.managed_api_base_id}/${var.acs_email_managed_api_name}"
        }
      },
      length(var.acs_email_connection_parameter_values) > 0 ? {
        parameterValues = var.acs_email_connection_parameter_values
      } : {}
    )
  }

  schema_validation_enabled = false
}

resource "azapi_resource" "azurevm" {
  type      = "Microsoft.Web/connections@2016-06-01"
  name      = local.name.api_connection_vm
  parent_id = local.management_rg_id
  location  = local.management_rg_location
  tags      = merge(local.management_tags, { ResourceType = "ApiConnection", Connector = "Azure-VM" })

  body = {
    properties = merge(
      {
        displayName = local.name.api_connection_vm
        api = {
          id = "${local.managed_api_base_id}/${var.azurevm_managed_api_name}"
        }
      },
      length(var.azurevm_connection_parameter_values) > 0 ? {
        parameterValues = var.azurevm_connection_parameter_values
      } : {}
    )
  }

  schema_validation_enabled = false
}

############################################
# 【管理】Logic Apps - auto_start_vm / auto_stop_vm
#   圖片未提供觸發程序與動作 definition，此處先建立可匯入 / 擴充的工作流程骨架。
############################################
resource "azurerm_logic_app_workflow" "auto_start_vm" {
  name                = local.name.logic_auto_start
  location            = local.management_rg_location
  resource_group_name = local.management_rg_name
  enabled             = var.logic_apps_enabled

  identity {
    type = "SystemAssigned"
  }

  tags = merge(local.management_tags, {
    ResourceType = "LogicAppWorkflow"
    Purpose      = "VM-Auto-Start"
  })
}

resource "azurerm_logic_app_workflow" "auto_stop_vm" {
  name                = local.name.logic_auto_stop
  location            = local.management_rg_location
  resource_group_name = local.management_rg_name
  enabled             = var.logic_apps_enabled

  identity {
    type = "SystemAssigned"
  }

  tags = merge(local.management_tags, {
    ResourceType = "LogicAppWorkflow"
    Purpose      = "VM-Auto-Stop"
  })
}

############################################
# 【管理】Activity Log Alert - Azure 服務健康狀態警示-Hub
############################################
resource "azurerm_monitor_activity_log_alert" "service_health" {
  name                = local.name.service_health_alert
  resource_group_name = local.management_rg_name
  location            = "global"
  scopes              = [local.subscription_scope]
  description         = "監控 Azure Service Health 事件：事故、維護、需採取動作與安全性事件"
  enabled             = var.service_health_alert_enabled

  tags = merge(local.management_tags, {
    ResourceType = "ActivityLogAlert"
    Purpose      = "Service-Health-Monitoring"
  })

  criteria {
    category = "ServiceHealth"

    service_health {
      events = ["Incident", "Maintenance", "ActionRequired", "Security"]
    }
  }

  dynamic "action" {
    for_each = var.alert_action_group_id != "" ? [var.alert_action_group_id] : []

    content {
      action_group_id = action.value
    }
  }
}
