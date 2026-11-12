############################################
# main.tf
#   Hub-Network-RG 測試環境獨立版本（不依賴任何其他資源群組）
#
#   建立並管理圖片中的 Hub-Network-RG 與五項測試資源：
#     Hub-VNET                  虛擬網路
#     LocalGateway              Local network gateway
#     ToFortiVPN                Connection
#     VPNGateway                Virtual network gateway
#     VPNGateway-IPaddress      公用 IP 位址
#
#   統一格式：
#     1. 命名一律經由 local.name 統一表，套用 local.prefix 前綴
#     2. 標籤一律以 merge(local.hub_tags, { ResourceType = ... }) 產生
#     3. 僅建立並管理圖片中的 Hub-Network-RG，不建立其他 RG
#     4. 資源群組名稱不套用前綴，但標籤一律套用
#     5. 不含 Bastion、Spoke VNet、Peering、Private DNS Zone Link、
#        Log Analytics 工作區與 Entra-Risky-SignIn 警示規則
############################################

locals {
  # 前綴：留空時不加分隔符號，例如 name_prefix = "demo" -> "demo-"
  prefix = var.name_prefix == "" ? "" : "${var.name_prefix}${var.name_separator}"

  # ---------- 統一命名表 ----------
  name = {
    # ===== Hub 網路層 =====
    hub_vnet          = "${local.prefix}Hub-VNET"
    gateway_subnet    = "GatewaySubnet" # Azure 保留名稱，不可加前綴
    vpn_gateway_pip   = "${local.prefix}VPNGateway-IPaddress"
    vpn_gateway       = "${local.prefix}VPNGateway"
    vpn_gateway_ipcfg = "${local.prefix}vpn-gateway-ipconfig"
    local_gateway     = "${local.prefix}LocalGateway"
    vpn_connection    = "${local.prefix}ToFortiVPN"
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

  # ---------- 資源群組解析（由 Terraform 建立並管理 Hub-Network-RG） ----------
  hub_rg_name     = azurerm_resource_group.hub.name
  hub_rg_location = azurerm_resource_group.hub.location
}

############################################
# 資源群組（由 Terraform 建立並管理；名稱不套用前綴）
############################################

resource "azurerm_resource_group" "hub" {
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
