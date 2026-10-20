############################################
# main.tf
#   Hub-Network-RG 獨立版本（不依賴任何其他資源群組）
#
#   對應入口網站 Hub-Network-RG 的七項資源：
#     Entra-Risky-SignIn        記錄搜尋警示規則
#     Hub-VNET                  虛擬網路
#     hub-vnet-bastion-IPaddress 公用 IP 位址
#     LocalGateway              Local network gateway
#     ToFortiVPN                Connection
#     VPNGateway                Virtual network gateway
#     VPNGateway-IPaddress      公用 IP 位址
#
#   統一格式：
#     1. 命名一律經由 local.name 統一表，套用 local.prefix 前綴
#     2. 標籤一律以 merge(local.hub_tags, { ResourceType = ... }) 產生
#     3. RG 名稱不套用前綴，但標籤一律套用
#     4. 支援 create_hub_resource_group 切換「新建 / 沿用既有」
#     5. 不含 Spoke VNet、Peering、Private DNS Zone Link，
#        Entra-Risky-SignIn 的資料來源（Log Analytics 工作區）
#        預設也建立在本 RG 內
############################################

locals {
  # 前綴：留空時不加分隔符號，例如 name_prefix = "demo" -> "demo-"
  prefix = var.name_prefix == "" ? "" : "${var.name_prefix}${var.name_separator}"

  # ---------- 統一命名表 ----------
  name = {
    # ===== Hub 網路層 =====
    hub_vnet          = "${local.prefix}Hub-VNET"
    gateway_subnet    = "GatewaySubnet" # Azure 保留名稱，不可加前綴
    hub_bastion_pip   = "${local.prefix}hub-vnet-bastion-IPaddress"
    vpn_gateway_pip   = "${local.prefix}VPNGateway-IPaddress"
    vpn_gateway       = "${local.prefix}VPNGateway"
    vpn_gateway_ipcfg = "${local.prefix}vpn-gateway-ipconfig"
    local_gateway     = "${local.prefix}LocalGateway"
    vpn_connection    = "${local.prefix}ToFortiVPN"

    # ===== 監控 =====
    log_analytics      = "${local.prefix}Hub-LAW"
    alert_risky_signin = "${local.prefix}Entra-Risky-SignIn"
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

  # Hub 專屬標籤（在共用標籤之上疊加）
  hub_tags = merge(local.common_tags, { Layer = "Network", Tier = "Hub" }, var.hub_tags)

  # ---------- 資源群組解析 ----------
  hub_rg_name     = var.create_hub_resource_group ? azurerm_resource_group.hub[0].name : data.azurerm_resource_group.hub_existing[0].name
  hub_rg_location = var.create_hub_resource_group ? azurerm_resource_group.hub[0].location : data.azurerm_resource_group.hub_existing[0].location

  # ---------- 警示資料來源 ----------
  alert_workspace_id = var.create_log_analytics_workspace ? azurerm_log_analytics_workspace.hub[0].id : var.log_analytics_workspace_id
}

############################################
# 資源群組（名稱不套用前綴，但一律套用統一標籤）
############################################

data "azurerm_resource_group" "hub_existing" {
  count = var.create_hub_resource_group ? 0 : 1
  name  = var.hub_resource_group_name
}

resource "azurerm_resource_group" "hub" {
  count    = var.create_hub_resource_group ? 1 : 0
  name     = var.hub_resource_group_name
  location = var.location

  tags = merge(local.hub_tags, {
    ResourceType = "ResourceGroup"
  })
}

############################################
# 【Hub】Virtual Network
############################################

resource "azurerm_virtual_network" "hub" {
  name                = local.name.hub_vnet
  location            = local.hub_rg_location
  resource_group_name = local.hub_rg_name
  address_space       = var.hub_vnet_address_space

  tags = merge(local.hub_tags, {
    ResourceType = "VirtualNetwork"
    Workload     = "Hub-Network"
  })
}

# VPN Gateway 專用子網路，名稱為 Azure 保留字，不可加前綴
resource "azurerm_subnet" "gateway" {
  count                = var.create_vpn_gateway ? 1 : 0
  name                 = local.name.gateway_subnet
  resource_group_name  = local.hub_rg_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = var.gateway_subnet_prefixes
}

############################################
# 【Hub】Bastion 公用 IP（Standard 靜態公用 IP）
#   對應入口網站：hub-vnet-bastion-IPaddress
############################################

resource "azurerm_public_ip" "hub_bastion" {
  count               = var.create_hub_bastion_public_ip ? 1 : 0
  name                = local.name.hub_bastion_pip
  location            = local.hub_rg_location
  resource_group_name = local.hub_rg_name
  allocation_method   = "Static"
  sku                 = "Standard"
  ip_version          = "IPv4"

  tags = merge(local.hub_tags, {
    ResourceType = "PublicIP"
    Purpose      = "Bastion-Frontend"
  })
}

############################################
# 【Hub】VPN Gateway
#   對應入口網站：VPNGateway / VPNGateway-IPaddress
############################################

resource "azurerm_public_ip" "vpn_gateway" {
  count               = var.create_vpn_gateway ? 1 : 0
  name                = local.name.vpn_gateway_pip
  location            = local.hub_rg_location
  resource_group_name = local.hub_rg_name
  allocation_method   = "Static"
  sku                 = "Standard"
  ip_version          = "IPv4"
  zones               = var.vpn_gateway_public_ip_zones

  tags = merge(local.hub_tags, {
    ResourceType = "PublicIP"
    Purpose      = "VPNGateway-Frontend"
  })
}

resource "azurerm_virtual_network_gateway" "vpn" {
  count               = var.create_vpn_gateway ? 1 : 0
  name                = local.name.vpn_gateway
  location            = local.hub_rg_location
  resource_group_name = local.hub_rg_name

  type          = "Vpn"
  vpn_type      = "RouteBased"
  active_active = false

  # azurerm 4.x：enable_bgp 已棄用並更名為 bgp_enabled，v5.0 將移除
  bgp_enabled = var.enable_bgp

  sku        = var.vpn_gateway_sku
  generation = "Generation2"

  tags = merge(local.hub_tags, {
    ResourceType = "VirtualNetworkGateway"
    Purpose      = "Site-to-Site"
  })

  ip_configuration {
    name                          = local.name.vpn_gateway_ipcfg
    public_ip_address_id          = azurerm_public_ip.vpn_gateway[0].id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway[0].id
  }
}

############################################
# 【Hub】Local Network Gateway（地端 FortiGate）
#   對應入口網站：LocalGateway
############################################

resource "azurerm_local_network_gateway" "fortigate" {
  count               = var.create_vpn_gateway ? 1 : 0
  name                = local.name.local_gateway
  location            = local.hub_rg_location
  resource_group_name = local.hub_rg_name

  gateway_address = var.onprem_vpn_public_ip
  address_space   = var.onprem_address_spaces

  tags = merge(local.hub_tags, {
    ResourceType = "LocalNetworkGateway"
    Purpose      = "OnPremises-FortiGate"
  })
}

############################################
# 【Hub】Site-to-Site IPsec Connection
#   對應入口網站：ToFortiVPN
############################################

resource "azurerm_virtual_network_gateway_connection" "fortigate" {
  count               = var.create_vpn_gateway && var.create_vpn_connection ? 1 : 0
  name                = local.name.vpn_connection
  location            = local.hub_rg_location
  resource_group_name = local.hub_rg_name

  type                       = "IPsec"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.vpn[0].id
  local_network_gateway_id   = azurerm_local_network_gateway.fortigate[0].id
  shared_key                 = var.vpn_shared_key

  # azurerm 4.x：enable_bgp 已棄用並更名為 bgp_enabled
  bgp_enabled = var.enable_bgp

  tags = merge(local.hub_tags, {
    ResourceType = "VpnConnection"
    Purpose      = "Site-to-Site"
  })
}

############################################
# 【Hub】Log Analytics 工作區
#   Entra-Risky-SignIn 警示規則的資料來源。
#   為了讓本 RG 完全獨立，預設建立於 Hub RG 內；
#   create_log_analytics_workspace = false 時改用既有工作區 ID。
############################################

resource "azurerm_log_analytics_workspace" "hub" {
  count               = var.create_risky_signin_alert && var.create_log_analytics_workspace ? 1 : 0
  name                = local.name.log_analytics
  location            = local.hub_rg_location
  resource_group_name = local.hub_rg_name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days

  tags = merge(local.hub_tags, {
    ResourceType = "LogAnalyticsWorkspace"
    Purpose      = "Security-Monitoring"
  })
}

############################################
# 【Hub】Entra-Risky-SignIn（記錄搜尋警示規則）
#   以 Scheduled Query Rule v2 偵測 Entra ID 中 / 高風險登入。
#   注意：Entra ID 的 SigninLogs 需另行在 Entra 診斷設定中
#         匯出至上述工作區，警示才會有資料可查詢。
############################################

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "risky_signin" {
  count               = var.create_risky_signin_alert ? 1 : 0
  name                = local.name.alert_risky_signin
  location            = local.hub_rg_location
  resource_group_name = local.hub_rg_name

  display_name         = local.name.alert_risky_signin
  description          = "偵測 Entra ID 中 / 高風險登入事件"
  enabled              = true
  severity             = var.risky_signin_alert_severity
  evaluation_frequency = var.risky_signin_alert_frequency
  window_duration      = var.risky_signin_alert_window
  scopes               = [local.alert_workspace_id]

  auto_mitigation_enabled = false

  tags = merge(local.hub_tags, {
    ResourceType = "ScheduledQueryRuleAlert"
    Purpose      = "Security-Monitoring"
  })

  criteria {
    query                   = var.risky_signin_alert_query
    time_aggregation_method = "Count"
    operator                = "GreaterThan"
    threshold               = 0

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  # 未指定 Action Group 時，不綁定任何通知（不沿用其他 RG 的 Action Group）
  dynamic "action" {
    for_each = var.alert_action_group_id != "" ? [var.alert_action_group_id] : []
    content {
      action_groups = [action.value]
    }
  }

  lifecycle {
    precondition {
      condition     = var.create_log_analytics_workspace || var.log_analytics_workspace_id != ""
      error_message = "create_log_analytics_workspace = false 時，必須提供 log_analytics_workspace_id。"
    }
  }
}
