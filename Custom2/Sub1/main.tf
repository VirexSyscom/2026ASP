############################################
# main.tf
#   Spoke 網路 + CRM 工作負載（含 SQL Managed Instance / Arc SQL）
#   + 遷移工具層（AzureMigrateRG）+ ADF-RG
#
#   統一格式：
#     1. 命名一律經由 local.name 統一表，套用 local.prefix 前綴
#     2. 標籤一律以 merge(local.<層>_tags, { ResourceType = ... }) 產生
#        例外：Private DNS Zone / VNet Link 限制最多 15 個標籤，
#        改用精簡的 local.dns_base_tags（見下方說明）
#     3. 四個資源群組獨立保留：Spoke 網路 / CRM / AzureMigrateRG / ADF-RG
#        RG 名稱一律不套用前綴，但標籤一律套用
#     4. 每個 RG 皆支援 create_<層>_resource_group 切換「新建 / 沿用既有」
#     5. CRM、ADF 的子網路一律沿用 Spoke 網路 RG 內的 Spoke-VNET
#
#   整合後資源：以原始主檔為基礎，SQL Server 清單改以 Arc SQL 資源名稱
#   對齊來源環境；不再建立無法與來源清單對應的 Azure SQL logical server。
#     Spoke-Network-RG (9)   nat-pip / Delete Security Rule (NSG) / Spoke-VNET /
#                            VirtualCluster* / rt-mssqlservermi / AP-Subnet-NSG /
#                            nsg-mssqlservermi / test-NSG / SpokeCRMNatGW
#     Spoke-CRM-RG           Compute Gallery 與映像 / SQL 受控執行個體與受控資料庫 /
#                            Arc 機器與 SQL Server 執行個體及資料庫 / NIC / 磁碟 /
#                            VM / 負載平衡器 / 警示規則 / Action Group / 受控識別
#     AzureMigrateRG (4)     RSV / Azure Migrate / Key Vault / 儲存體
#     ADF-RG (13)            私人 DNS 區域 / Private Endpoint(+NIC) / Key Vault /
#                            Data Factory / NSG / 儲存體
#
#   不由 Terraform 直接建立的項目：
#     - VirtualCluster*：建立 SQL 受控執行個體時由 Azure 自動產生
#     - Private Endpoint 的 NIC：由 Private Endpoint 自動產生（adf-pe-nic 除外，
#       因入口網站現況為自訂名稱，此處以 custom_network_interface_name 指定）
#
#   以 azapi 建立「資源紀錄」的項目（不需真實主機連線）：
#     - Arc 機器 / SQL Server 執行個體 / 5 個資料庫，見 var.create_arc_sql_resources
############################################

data "azurerm_client_config" "current" {}

locals {
  # 前綴：留空時不加分隔符號，例如 name_prefix = "demo" -> "demo-"
  prefix = var.name_prefix == "" ? "" : "${var.name_prefix}${var.name_separator}"

  # 供不允許連字號的資源（儲存體、Compute Gallery、受控執行個體）使用的緊湊前綴
  prefix_compact = lower(replace(var.name_prefix, "-", ""))

  # ---------- 統一命名表 ----------
  name = {
    # ===== Spoke 網路層 =====
    spoke_vnet            = "${local.prefix}Spoke-VNET"
    ap_subnet             = "${local.prefix}AP-Subnet"
    mi_subnet             = "${local.prefix}MI-Subnet"
    pe_subnet             = "${local.prefix}PrivateEndpoint-Subnet"
    ap_nsg                = "${local.prefix}AP-Subnet-NSG"
    mi_nsg                = "${local.prefix}nsg-mssqlservermi"
    test_nsg              = "${local.prefix}test-NSG"
    mi_route_table        = "${local.prefix}rt-mssqlservermi"
    nat_pip               = "${local.prefix}nat-pip"
    nat_gateway           = "${local.prefix}SpokeCRMNatGW"
    alert_nsg_rule_delete = "${local.prefix}Delete Security Rule (NSG)"

    # ===== CRM 工作負載層 =====
    vm_identity      = "${local.prefix}vm-user-mid"
    lb               = "${local.prefix}CRMAP-LB"
    lb_frontend      = "${local.prefix}private-frontend"
    lb_backend_pool  = "${local.prefix}crm-backend-pool"
    lb_probe         = "${local.prefix}https-probe"
    lb_rule          = "${local.prefix}https-rule"
    nic_ipconfig     = "${local.prefix}ipconfig1"
    compute_gallery  = "${local.prefix_compact}CRMGallery"
    shared_image     = "${local.prefix}CRM-VM"
    image_snapshot   = "${local.prefix}CRM-image-source-snapshot"
    asr_seed_disk    = "${local.prefix}${var.asr_seed_disk_name}"
    managed_instance = "${local.prefix_compact}${var.mi_name}${random_string.mi_suffix.result}"
    managed_database = "${local.prefix}${var.crm_database_name}"
    arc_machine      = "${local.prefix}${var.arc_machine_name}"
    arc_sql_instance = "${local.prefix}${var.arc_machine_name}"
    alert_cpu        = "${local.prefix}Percentage CPU more ${var.cpu_alert_threshold}"
    alert_vm_avail   = "${local.prefix}VM Availability"
    alert_crm_db_cpu = "${local.prefix}CRM-DB CPU"

    # ===== 遷移工具層（AzureMigrateRG）=====
    # 對應入口網站清單：
    #   discovervmware8406vault / Migrate-CRM / Migrate-CRM5539kv / migratecrmlog
    migrate_project = "${local.prefix}${var.migrate_project_name}"
    recovery_vault  = "${local.prefix}${var.recovery_vault_name}${random_string.migrate_suffix.result}vault"
    migrate_kv      = substr("${local.prefix_compact}${var.migrate_key_vault_name}${random_string.migrate_suffix.result}kv", 0, 24)
    migrate_storage = substr("${local.prefix_compact}${lower(var.migrate_storage_name)}${random_string.migrate_suffix.result}", 0, 24)

    # ===== ADF-RG =====
    adf         = "${local.prefix}${var.adf_name}-${random_string.adf_suffix.result}"
    adf_kv      = substr("${local.prefix}${var.adf_key_vault_name}-${random_string.adf_suffix.result}", 0, 24)
    adf_storage = substr("${local.prefix_compact}${lower(var.adf_storage_name)}${random_string.adf_suffix.result}", 0, 24)
    adf_nsg     = "${local.prefix}${var.adf_nsg_name}"
    adf_pe      = "${local.prefix}adf-pe"
    adf_pe_nic  = "${local.prefix}adf-pe-nic"
    adf_blob_pe = "${local.prefix}pe-${lower(var.adf_storage_name)}-blob"
    adf_dfs_pe  = "${local.prefix}pe-${lower(var.adf_storage_name)}-dfs"
    adf_kv_pe   = "${local.prefix}pe-${var.adf_key_vault_name}"
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

  # 各層專屬標籤（在共用標籤之上疊加）
  network_tags = merge(local.common_tags, { Layer = "Network", Tier = "Spoke" }, var.network_tags)
  crm_tags     = merge(local.common_tags, { Layer = "Workload", Workload = "CRM" }, var.crm_tags)
  migrate_tags = merge(local.common_tags, { Layer = "Migration", Workload = "AzureMigrate" }, var.migrate_tags)
  adf_tags     = merge(local.common_tags, { Layer = "Workload", Workload = "DataFactory" }, var.adf_tags)

  # ---------- Private DNS 專用精簡標籤 ----------
  # Private DNS Zone / VNet Link 最多只允許 15 個標籤（其他資源為 50 個），
  # 若沿用 local.adf_tags（含 var.tags / var.adf_tags）容易超過上限，
  # 回傳 400 BadRequest: The resource tags are invalid。
  # 因此只保留必要標籤，固定最多 6 個。
  dns_base_tags = merge(
    {
      Environment = var.environment
      Owner       = var.owner
      ManagedBy   = "Terraform"
    },
    var.cost_center == "" ? {} : { CostCenter = var.cost_center }
  )

  # ---------- 資源群組解析 ----------
  network_rg_name     = var.create_network_resource_group ? azurerm_resource_group.network[0].name : data.azurerm_resource_group.network_existing[0].name
  network_rg_location = var.create_network_resource_group ? azurerm_resource_group.network[0].location : data.azurerm_resource_group.network_existing[0].location

  crm_rg_name     = var.create_crm_resource_group ? azurerm_resource_group.crm[0].name : data.azurerm_resource_group.crm_existing[0].name
  crm_rg_location = var.create_crm_resource_group ? azurerm_resource_group.crm[0].location : data.azurerm_resource_group.crm_existing[0].location
  crm_rg_id       = var.create_crm_resource_group ? azurerm_resource_group.crm[0].id : data.azurerm_resource_group.crm_existing[0].id

  migrate_rg_name     = var.create_migrate_resource_group ? azurerm_resource_group.migrate[0].name : data.azurerm_resource_group.migrate_existing[0].name
  migrate_rg_location = var.create_migrate_resource_group ? azurerm_resource_group.migrate[0].location : data.azurerm_resource_group.migrate_existing[0].location
  migrate_rg_id       = var.create_migrate_resource_group ? azurerm_resource_group.migrate[0].id : data.azurerm_resource_group.migrate_existing[0].id

  adf_rg_name     = var.create_adf_resource_group ? azurerm_resource_group.adf[0].name : data.azurerm_resource_group.adf_existing[0].name
  adf_rg_location = var.create_adf_resource_group ? azurerm_resource_group.adf[0].location : data.azurerm_resource_group.adf_existing[0].location

  alert_scope = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"

  # 映像版本的來源 VM（取 var.vms 的 crm）
  image_source_vm_key = "crm"

  # 未由 TF_VAR_* 或 tfvars 指定時，優先採用寫入 state 後固定的 Random 密碼。
  effective_admin_password             = var.admin_password != null ? var.admin_password : random_password.admin[0].result
  effective_sql_administrator_password = var.sql_administrator_password != null ? var.sql_administrator_password : random_password.sql_administrator[0].result
}

############################################
# 全域唯一名稱用亂數後綴
############################################
# VM 與 SQL 密碼：未傳入自訂密碼時產生高強度亂數，結果寫入 Terraform state 後固定。
resource "random_password" "admin" {
  count = var.admin_password == null ? 1 : 0

  length           = 24
  special          = true
  override_special = "!@#%"
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}

resource "random_password" "sql_administrator" {
  count = var.sql_administrator_password == null ? 1 : 0

  length           = 24
  special          = true
  override_special = "!@#%"
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}

# SQL 受控執行個體（DNS 名稱需全域唯一）
resource "random_string" "mi_suffix" {
  length  = 4
  upper   = false
  special = false

  keepers = {
    prefix = local.prefix
  }
}

# 遷移層共用後綴（RSV / Key Vault / Storage）
resource "random_string" "migrate_suffix" {
  length  = 4
  upper   = false
  special = false

  keepers = {
    prefix = local.prefix
  }
}

# ADF-RG 共用後綴（Data Factory / Key Vault / Storage）
resource "random_string" "adf_suffix" {
  length  = 4
  upper   = false
  special = false

  keepers = {
    prefix = local.prefix
  }
}

############################################
# 資源群組（四個獨立 RG，名稱皆不套用前綴，但一律套用統一標籤）
#   1. Spoke 網路  var.network_resource_group_name
#   2. CRM         var.crm_resource_group_name
#   3. 遷移工具    var.migrate_resource_group_name（AzureMigrateRG）
#   4. ADF         var.adf_resource_group_name
############################################
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

data "azurerm_resource_group" "crm_existing" {
  count = var.create_crm_resource_group ? 0 : 1
  name  = var.crm_resource_group_name
}

resource "azurerm_resource_group" "crm" {
  count    = var.create_crm_resource_group ? 1 : 0
  name     = var.crm_resource_group_name
  location = var.location

  tags = merge(local.crm_tags, {
    ResourceType = "ResourceGroup"
  })
}

data "azurerm_resource_group" "migrate_existing" {
  count = var.create_migrate_resource_group ? 0 : 1
  name  = var.migrate_resource_group_name
}

resource "azurerm_resource_group" "migrate" {
  count    = var.create_migrate_resource_group ? 1 : 0
  name     = var.migrate_resource_group_name
  location = var.location

  tags = merge(local.migrate_tags, {
    ResourceType = "ResourceGroup"
  })
}

data "azurerm_resource_group" "adf_existing" {
  count = var.create_adf_resource_group ? 0 : 1
  name  = var.adf_resource_group_name
}

resource "azurerm_resource_group" "adf" {
  count    = var.create_adf_resource_group ? 1 : 0
  name     = var.adf_resource_group_name
  location = var.location

  tags = merge(local.adf_tags, {
    ResourceType = "ResourceGroup"
  })
}

############################################
# 【Spoke 網路】Virtual Network - Spoke-VNET
############################################
resource "azurerm_virtual_network" "spoke" {
  name                = local.name.spoke_vnet
  location            = local.network_rg_location
  resource_group_name = local.network_rg_name
  address_space       = var.spoke_vnet_address_space

  tags = merge(local.network_tags, {
    ResourceType = "VirtualNetwork"
    Workload     = "Production"
  })
}

resource "azurerm_subnet" "ap" {
  name                 = local.name.ap_subnet
  resource_group_name  = local.network_rg_name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [var.ap_subnet_prefix]
}

# SQL 受控執行個體專用子網路（需委派，不可與其他資源共用）
resource "azurerm_subnet" "mi" {
  name                 = local.name.mi_subnet
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

resource "azurerm_subnet" "pe" {
  name                              = local.name.pe_subnet
  resource_group_name               = local.network_rg_name
  virtual_network_name              = azurerm_virtual_network.spoke.name
  address_prefixes                  = [var.pe_subnet_prefix]
  private_endpoint_network_policies = "Disabled"
}

############################################
# 【Spoke 網路】Network Security Group
############################################
resource "azurerm_network_security_group" "ap" {
  name                = local.name.ap_nsg
  location            = local.network_rg_location
  resource_group_name = local.network_rg_name

  tags = merge(local.network_tags, {
    ResourceType = "NetworkSecurityGroup"
    SubnetTier   = "Application"
  })

  security_rule {
    name                       = "Allow-HTTPS-Inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Deny-Internet-Inbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "ap" {
  subnet_id                 = azurerm_subnet.ap.id
  network_security_group_id = azurerm_network_security_group.ap.id
}

# 測試用 NSG（入口網站現況為獨立 NSG，未綁定子網路）
resource "azurerm_network_security_group" "test" {
  name                = local.name.test_nsg
  location            = local.network_rg_location
  resource_group_name = local.network_rg_name

  tags = merge(local.network_tags, {
    ResourceType = "NetworkSecurityGroup"
    Purpose      = "Test"
  })
}

############################################
# 【Spoke 網路】SQL 受控執行個體專用 NSG 與路由表
#   對應入口網站：nsg-mssqlservermi / rt-mssqlservermi
#   規則依 azurerm_mssql_managed_instance 官方範例；
#   MI 建立後 Azure 會再自動加入 Microsoft.Sql-managedInstances_UseOnly_* 規則與路由，
#   NSG 規則採獨立資源、路由表以 ignore_changes 避免產生漂移。
############################################
resource "azurerm_network_security_group" "mi" {
  name                = local.name.mi_nsg
  location            = local.network_rg_location
  resource_group_name = local.network_rg_name

  tags = merge(local.network_tags, {
    ResourceType = "NetworkSecurityGroup"
    SubnetTier   = "ManagedInstance"
  })
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
  resource_group_name         = local.network_rg_name
  network_security_group_name = azurerm_network_security_group.mi.name
}

resource "azurerm_network_security_rule" "mi_allow_misubnet_inbound" {
  name                        = "allow_misubnet_inbound"
  priority                    = 200
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = var.mi_subnet_prefix
  destination_address_prefix  = "*"
  resource_group_name         = local.network_rg_name
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
  resource_group_name         = local.network_rg_name
  network_security_group_name = azurerm_network_security_group.mi.name
}

# 允許 Spoke-VNET 內（AP-Subnet 的 CRM VM）以 TDS 連線 SQL 受控執行個體
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
  resource_group_name         = local.network_rg_name
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
  resource_group_name         = local.network_rg_name
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
  resource_group_name         = local.network_rg_name
  network_security_group_name = azurerm_network_security_group.mi.name
}

resource "azurerm_network_security_rule" "mi_allow_misubnet_outbound" {
  name                        = "allow_misubnet_outbound"
  priority                    = 200
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = var.mi_subnet_prefix
  resource_group_name         = local.network_rg_name
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
  resource_group_name         = local.network_rg_name
  network_security_group_name = azurerm_network_security_group.mi.name
}

resource "azurerm_route_table" "mi" {
  name                          = local.name.mi_route_table
  location                      = local.network_rg_location
  resource_group_name           = local.network_rg_name
  bgp_route_propagation_enabled = true

  tags = merge(local.network_tags, {
    ResourceType = "RouteTable"
    SubnetTier   = "ManagedInstance"
  })

  # MI 建立後由 Azure 自動寫入路由，不納入 Terraform 管理
  lifecycle {
    ignore_changes = [route]
  }
}

resource "azurerm_subnet_network_security_group_association" "mi" {
  subnet_id                 = azurerm_subnet.mi.id
  network_security_group_id = azurerm_network_security_group.mi.id

  depends_on = [
    azurerm_network_security_rule.mi_allow_management_inbound,
    azurerm_network_security_rule.mi_allow_misubnet_inbound,
    azurerm_network_security_rule.mi_allow_health_probe_inbound,
    azurerm_network_security_rule.mi_allow_tds_inbound,
    azurerm_network_security_rule.mi_deny_all_inbound,
    azurerm_network_security_rule.mi_allow_management_outbound,
    azurerm_network_security_rule.mi_allow_misubnet_outbound,
    azurerm_network_security_rule.mi_deny_all_outbound,
  ]
}

resource "azurerm_subnet_route_table_association" "mi" {
  subnet_id      = azurerm_subnet.mi.id
  route_table_id = azurerm_route_table.mi.id
}

############################################
# 【Spoke 網路】NAT Gateway
#   對應入口網站：nat-pip / SpokeCRMNatGW
############################################
resource "azurerm_public_ip" "nat" {
  name                = local.name.nat_pip
  location            = local.network_rg_location
  resource_group_name = local.network_rg_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]

  tags = merge(local.network_tags, {
    ResourceType = "PublicIP"
    Purpose      = "NAT-Egress"
  })
}

resource "azurerm_nat_gateway" "spoke" {
  name                    = local.name.nat_gateway
  location                = local.network_rg_location
  resource_group_name     = local.network_rg_name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 4

  tags = merge(local.network_tags, {
    ResourceType = "NatGateway"
    Purpose      = "Outbound-Connectivity"
  })
}

resource "azurerm_nat_gateway_public_ip_association" "spoke" {
  nat_gateway_id       = azurerm_nat_gateway.spoke.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_subnet_nat_gateway_association" "ap" {
  subnet_id      = azurerm_subnet.ap.id
  nat_gateway_id = azurerm_nat_gateway.spoke.id
}

############################################
# 【Spoke 網路】Activity Log Alert（location 固定 global）
#   對應入口網站：Delete Security Rule (NSG)
#   alert_action_group_id 留空時不綁定通知
############################################
resource "azurerm_monitor_activity_log_alert" "nsg_rule_delete" {
  name                = local.name.alert_nsg_rule_delete
  resource_group_name = local.network_rg_name
  location            = "global"
  scopes              = [local.alert_scope]
  description         = "當 NSG 的安全性規則被刪除時觸發"
  enabled             = true

  tags = merge(local.network_tags, {
    ResourceType = "ActivityLogAlert"
    Purpose      = "Security-Monitoring"
  })

  criteria {
    category       = "Administrative"
    operation_name = "Microsoft.Network/networkSecurityGroups/securityRules/delete"
  }

  dynamic "action" {
    for_each = var.alert_action_group_id != "" ? [var.alert_action_group_id] : []

    content {
      action_group_id = action.value
    }
  }
}

############################################
# 【CRM】受控識別
#   對應入口網站：vm-user-mid
############################################
resource "azurerm_user_assigned_identity" "vm" {
  name                = local.name.vm_identity
  location            = local.crm_rg_location
  resource_group_name = local.crm_rg_name

  tags = merge(local.crm_tags, {
    ResourceType = "ManagedIdentity"
  })
}

############################################
# 【CRM】Load Balancer（內部，前端位於 AP-Subnet）
#   對應入口網站：CRMAP-LB
############################################
resource "azurerm_lb" "crm" {
  name                = local.name.lb
  location            = local.crm_rg_location
  resource_group_name = local.crm_rg_name
  sku                 = "Standard"

  tags = merge(local.crm_tags, {
    ResourceType = "LoadBalancer"
    SubnetTier   = "Application"
  })

  frontend_ip_configuration {
    name                          = local.name.lb_frontend
    subnet_id                     = azurerm_subnet.ap.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_lb_backend_address_pool" "crm" {
  name            = local.name.lb_backend_pool
  loadbalancer_id = azurerm_lb.crm.id
}

resource "azurerm_lb_probe" "https" {
  name            = local.name.lb_probe
  loadbalancer_id = azurerm_lb.crm.id
  protocol        = "Tcp"
  port            = 443
}

resource "azurerm_lb_rule" "https" {
  name                           = local.name.lb_rule
  loadbalancer_id                = azurerm_lb.crm.id
  protocol                       = "Tcp"
  frontend_port                  = 443
  backend_port                   = 443
  frontend_ip_configuration_name = local.name.lb_frontend
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.crm.id]
  probe_id                       = azurerm_lb_probe.https.id
}

############################################
# 【CRM】虛擬機器（掛載 Spoke-VNET 的 AP-Subnet）
#   對應入口網站：CRM / CRM02 與其 NIC、OS 磁碟
############################################
resource "azurerm_network_interface" "crm" {
  for_each = var.vms

  name                = "${local.prefix}${each.value.nic_name}"
  location            = local.crm_rg_location
  resource_group_name = local.crm_rg_name

  tags = merge(local.crm_tags, {
    ResourceType = "NetworkInterface"
  })

  ip_configuration {
    name                          = local.name.nic_ipconfig
    subnet_id                     = azurerm_subnet.ap.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface_backend_address_pool_association" "crm" {
  for_each = var.vms

  network_interface_id    = azurerm_network_interface.crm[each.key].id
  ip_configuration_name   = local.name.nic_ipconfig
  backend_address_pool_id = azurerm_lb_backend_address_pool.crm.id
}

resource "azurerm_windows_virtual_machine" "crm" {
  for_each = var.vms

  name                  = "${local.prefix}${each.value.name}"
  computer_name         = substr(replace("${local.prefix}${each.value.name}", "-", ""), 0, 15)
  location              = local.crm_rg_location
  resource_group_name   = local.crm_rg_name
  size                  = var.vm_size
  admin_username        = var.admin_username
  admin_password        = local.effective_admin_password
  network_interface_ids = [azurerm_network_interface.crm[each.key].id]

  tags = merge(local.crm_tags, {
    ResourceType = "VirtualMachine"
    SubnetTier   = "Application"
  })

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.vm.id]
  }

  os_disk {
    name                 = "${local.prefix}${each.value.os_disk_name}"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }
}

############################################
# 【CRM】ASR 種子磁碟
#   對應入口網站：asrseeddisk-CRM02-102_WS20-<guid>
#   原本由 ASR / Azure Migrate 啟用複寫時自動建立（Empty 磁碟），
#   此處保留以對齊現況；不需要請將 create_asr_seed_disk 設為 false。
############################################
resource "azurerm_managed_disk" "asr_seed" {
  count = var.create_asr_seed_disk ? 1 : 0

  name                 = local.name.asr_seed_disk
  location             = local.crm_rg_location
  resource_group_name  = local.crm_rg_name
  storage_account_type = var.asr_seed_disk_storage_type
  create_option        = "Empty"
  disk_size_gb         = var.asr_seed_disk_size_gb

  tags = merge(local.crm_tags, {
    ResourceType = "ManagedDisk"
    Purpose      = "ASR-Seed"
  })
}

############################################
# 【CRM】Compute Gallery
#   對應入口網站：CRMGallery / CRM-VM（映像定義）/ 0.0.1（映像版本）
#
#   映像版本必須有來源：此處對 CRM VM 的 OS 磁碟建立快照（額外資源，入口網站清單
#   中沒有），再以快照建立 0.0.1。來源為「執行中、未一般化」的 VM，
#   因此映像定義需為 specialized。
############################################
resource "azurerm_shared_image_gallery" "crm" {
  name                = local.name.compute_gallery
  resource_group_name = local.crm_rg_name
  location            = local.crm_rg_location
  description         = "CRM VM image gallery"

  tags = merge(local.crm_tags, {
    ResourceType = "ComputeGallery"
  })
}

resource "azurerm_shared_image" "crm" {
  name                = local.name.shared_image
  gallery_name        = azurerm_shared_image_gallery.crm.name
  resource_group_name = local.crm_rg_name
  location            = local.crm_rg_location
  os_type             = "Windows"
  hyper_v_generation  = "V2"
  specialized         = true

  tags = merge(local.crm_tags, {
    ResourceType = "SharedImage"
  })

  identifier {
    publisher = "CM"
    offer     = "CRM"
    sku       = "CRM-VM"
  }
}

data "azurerm_managed_disk" "crm_image_source" {
  count = var.create_crm_image_version ? 1 : 0

  name                = "${local.prefix}${var.vms[local.image_source_vm_key].os_disk_name}"
  resource_group_name = local.crm_rg_name

  depends_on = [azurerm_windows_virtual_machine.crm]
}

resource "azurerm_snapshot" "crm_image_source" {
  count = var.create_crm_image_version ? 1 : 0

  name                = local.name.image_snapshot
  location            = local.crm_rg_location
  resource_group_name = local.crm_rg_name
  create_option       = "Copy"
  source_resource_id  = data.azurerm_managed_disk.crm_image_source[0].id

  tags = merge(local.crm_tags, {
    ResourceType = "Snapshot"
    Purpose      = "GalleryImageSource"
  })
}

resource "azurerm_shared_image_version" "crm" {
  count = var.create_crm_image_version ? 1 : 0

  name                = var.crm_image_version
  gallery_name        = azurerm_shared_image_gallery.crm.name
  image_name          = azurerm_shared_image.crm.name
  resource_group_name = local.crm_rg_name
  location            = local.crm_rg_location
  os_disk_snapshot_id = azurerm_snapshot.crm_image_source[0].id

  target_region {
    name                   = local.crm_rg_location
    regional_replica_count = 1
    storage_account_type   = "Standard_LRS"
  }

  tags = merge(local.crm_tags, {
    ResourceType = "SharedImageVersion"
  })
}

############################################
# 【CRM】SQL 受控執行個體 + 受控資料庫
#   對應入口網站：mssqlservermi（SQL 受控執行個體）
#                 CRMData (mssqlservermi/CRMData)（受控資料庫）
#   VirtualCluster* 由 Azure 在建立受控執行個體時自動產生，不需也無法在此宣告。
#   首次建立受控執行個體通常需數十分鐘到數小時。
#   受控資料庫資源不輸出 tags，故不套用標籤。
############################################
resource "azurerm_mssql_managed_instance" "crm" {
  name                = local.name.managed_instance
  resource_group_name = local.crm_rg_name
  location            = local.crm_rg_location
  subnet_id           = azurerm_subnet.mi.id

  administrator_login          = var.sql_administrator_login
  administrator_login_password = local.effective_sql_administrator_password

  license_type                 = var.mi_license_type
  sku_name                     = var.mi_sku_name
  vcores                       = var.mi_vcores
  storage_size_in_gb           = var.mi_storage_size_in_gb
  minimum_tls_version          = "1.2"
  public_data_endpoint_enabled = false

  tags = merge(local.crm_tags, {
    ResourceType = "SqlManagedInstance"
    SubnetTier   = "ManagedInstance"
  })

  depends_on = [
    azurerm_subnet_network_security_group_association.mi,
    azurerm_subnet_route_table_association.mi,
  ]
}

resource "azurerm_mssql_managed_database" "crm" {
  name                = local.name.managed_database
  managed_instance_id = azurerm_mssql_managed_instance.crm.id
}

############################################
# 【CRM】Azure Arc SQL Server（不需真實主機連線）
#   對應入口網站：
#     CRM-DB（Machine - Azure Arc）
#     CRM-DB（SQL Server 執行個體）
#     CRMData / master / model / msdb / tempdb（SQL Server 資料庫）
#   以 azapi 直接建立 ARM 資源紀錄，只有中繼資料；不會安裝 Arc Agent，
#   Portal 顯示的版本、狀態皆為 var.arc_sql_* 的靜態值。
#   部署前需註冊 Microsoft.HybridCompute 與 Microsoft.AzureArcData。
#   schema_validation_enabled = false：避免 azapi 內建 schema 與 API 版本不符而擋下。
############################################
# vmId 以 random_uuid 產生（寫入 state 後固定）；clientPublicKey 為一次性產生的 RSA-2048 公鑰（Base64 DER，不含私鑰）
resource "random_uuid" "arc_machine_vm_id" {
  count = var.create_arc_sql_resources ? 1 : 0
}

locals {
  arc_machine_client_public_key = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAwNnb65ThyVlL0s/lKDVULK0h+AITiAiOaD2oCXZund09aBoa016bEUO5FU0F8XeYDdVlkzFhLkxrg2WO+0vtzNXCteW5iff1uZdYTkG8YPyO590naLIxaLsXR4EmRwJmMslBr16s92yrDv/FgytIrgtFsZatV2us0+7iT+jUxcImzSkzAJoBWgq98tIUaXXSo4IW/3XtDZhjttX4p5qIHWQqugxoonFRuEQfTIbYWfXJ8Hq5lgqKhvT3zqJLeVsQFqFQdzKgwBrJ1nBfidtlSduWl8gEk/AAzY42psa1SlaIOl1KtOWWDsfc/d2zQNo+ebQUmE9Wv3CnKJqzPDpudQIDAQAB"
}

resource "azapi_resource" "arc_machine" {
  count = var.create_arc_sql_resources ? 1 : 0

  type      = "Microsoft.HybridCompute/machines@2024-07-10"
  name      = local.name.arc_machine
  location  = local.crm_rg_location
  parent_id = local.crm_rg_id

  # 【修正】HCRP400: Managed Identity
  identity {
    type = "SystemAssigned"
  }

  # 【修正】HCRP400: VmId, ClientPublicKey
  body = {
    properties = {
      osType          = "windows"
      vmId            = random_uuid.arc_machine_vm_id[0].result
      clientPublicKey = local.arc_machine_client_public_key
    }
  }

  tags = merge(local.crm_tags, {
    ResourceType = "ArcMachine"
    Purpose      = "SQL-Server-Host"
  })

  schema_validation_enabled = false
}

resource "azapi_resource" "arc_sql_instance" {
  count = var.create_arc_sql_resources ? 1 : 0

  type      = "Microsoft.AzureArcData/sqlServerInstances@2024-01-01"
  name      = local.name.arc_sql_instance
  location  = local.crm_rg_location
  parent_id = local.crm_rg_id

  # containerResourceId 與 status 為 API 必填欄位
  body = {
    properties = {
      containerResourceId = azapi_resource.arc_machine[0].id
      status              = var.arc_sql_status
      edition             = var.arc_sql_edition
      version             = var.arc_sql_version
      instanceName        = local.name.arc_sql_instance
    }
  }

  tags = merge(local.crm_tags, {
    ResourceType = "ArcSqlServerInstance"
  })

  schema_validation_enabled = false
}

# 5 個 SQL Server 資料庫（CRMData + 4 個系統資料庫）。
# 名稱由 arc_sql_database_names 明確指定，對齊來源環境：
# CRMData / master / model / msdb / tempdb。
locals {
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
}

resource "azapi_resource" "arc_sql_database" {
  for_each = var.create_arc_sql_resources ? local.arc_sql_databases : {}

  type      = "Microsoft.AzureArcData/sqlServerInstances/databases@2024-01-01"
  name      = each.key
  location  = local.crm_rg_location
  parent_id = azapi_resource.arc_sql_instance[0].id

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

  tags = merge(local.crm_tags, {
    ResourceType = "ArcSqlServerDatabase"
  })

  schema_validation_enabled = false

  depends_on = [azapi_resource.arc_sql_instance]
}

############################################
# 【CRM】監控
#   對應入口網站：CRM-DB CPU / Percentage CPU more 1 / VM Availability /
#                 VM Availability - crm / VM Availability - crm02 /
#                 VMI-ActionGroup-crm / VMI-ActionGroup-crm02
#   每台 VM 都有獨立 Action Group 與可用性警示；Action Group 預設不含
#   收件者，可於 Azure Portal 或後續 Terraform 變更加入通知管道。
#   alert_action_group_id 只供既有兩條共用警示選擇性綁定外部 Action Group。
############################################
resource "azurerm_monitor_action_group" "vm" {
  for_each = var.vms

  name                = "${local.prefix}VMI-ActionGroup-${lower(each.value.name)}"
  resource_group_name = local.crm_rg_name
  short_name          = substr("vmi-${lower(each.key)}", 0, 12)
  enabled             = true

  tags = merge(local.crm_tags, {
    ResourceType = "ActionGroup"
    VirtualMachine = each.value.name
  })
}

resource "azurerm_monitor_metric_alert" "crm_db_cpu" {
  name                     = local.name.alert_crm_db_cpu
  resource_group_name      = local.crm_rg_name
  scopes                   = [azurerm_mssql_managed_instance.crm.id]
  target_resource_type     = "Microsoft.Sql/managedInstances"
  target_resource_location = local.crm_rg_location
  severity                 = 2
  frequency                = "PT5M"
  window_size              = "PT15M"
  enabled                  = true
  auto_mitigate            = true

  tags = merge(local.crm_tags, {
    ResourceType = "MetricAlert"
    Purpose      = "Database-Performance-Monitoring"
  })

  criteria {
    metric_namespace = "Microsoft.Sql/managedInstances"
    metric_name      = "avg_cpu_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.cpu_alert_threshold
  }

  dynamic "action" {
    for_each = azurerm_monitor_action_group.vm

    content {
      action_group_id = action.value.id
    }
  }
}

resource "azurerm_monitor_metric_alert" "cpu" {
  name                     = local.name.alert_cpu
  resource_group_name      = local.crm_rg_name
  scopes                   = [for vm in azurerm_windows_virtual_machine.crm : vm.id]
  target_resource_type     = "Microsoft.Compute/virtualMachines"
  target_resource_location = local.crm_rg_location
  severity                 = 2
  frequency                = "PT5M"
  window_size              = "PT15M"

  tags = merge(local.crm_tags, {
    ResourceType = "MetricAlert"
    Purpose      = "Performance-Monitoring"
  })

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.cpu_alert_threshold
  }

  dynamic "action" {
    for_each = var.alert_action_group_id != "" ? [var.alert_action_group_id] : []

    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "vm_availability" {
  name                     = local.name.alert_vm_avail
  resource_group_name      = local.crm_rg_name
  scopes                   = [for vm in azurerm_windows_virtual_machine.crm : vm.id]
  target_resource_type     = "Microsoft.Compute/virtualMachines"
  target_resource_location = local.crm_rg_location
  severity                 = 1
  frequency                = "PT1M"
  window_size              = "PT5M"

  tags = merge(local.crm_tags, {
    ResourceType = "MetricAlert"
    Purpose      = "Availability-Monitoring"
  })

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "VmAvailabilityMetric"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 1
  }

  dynamic "action" {
    for_each = var.alert_action_group_id != "" ? [var.alert_action_group_id] : []

    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "vm_availability_individual" {
  for_each = var.vms

  name                     = "${local.prefix}VM Availability - ${lower(each.value.name)}"
  resource_group_name      = local.crm_rg_name
  scopes                   = [azurerm_windows_virtual_machine.crm[each.key].id]
  target_resource_type     = "Microsoft.Compute/virtualMachines"
  target_resource_location = local.crm_rg_location
  severity                 = 1
  frequency                = "PT1M"
  window_size              = "PT5M"
  enabled                  = true
  auto_mitigate            = true

  tags = merge(local.crm_tags, {
    ResourceType   = "MetricAlert"
    Purpose        = "Availability-Monitoring"
    VirtualMachine = each.value.name
  })

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "VmAvailabilityMetric"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 1
  }

  action {
    action_group_id = azurerm_monitor_action_group.vm[each.key].id
  }
}

############################################
# 【遷移工具層 / AzureMigrateRG】復原服務保存庫
#   對應入口網站：discovervmware8406vault（復原服務保存庫）
############################################
resource "azurerm_recovery_services_vault" "migrate" {
  name                          = local.name.recovery_vault
  location                      = local.migrate_rg_location
  resource_group_name           = local.migrate_rg_name
  sku                           = var.recovery_vault_sku
  storage_mode_type             = var.recovery_vault_storage_mode
  public_network_access_enabled = true

  identity {
    type = "SystemAssigned"
  }

  tags = merge(local.migrate_tags, {
    ResourceType = "RecoveryServicesVault"
    Purpose      = "VMware-Discovery-Migration"
  })
}

############################################
# 【遷移工具層 / AzureMigrateRG】Azure Migrate 專案
#   對應入口網站：Migrate-CRM（Azure Migrate）
#
#   azurerm 未提供對應資源，改以 azapi 呼叫。
#   注意：Microsoft.Migrate/migrateProjects 在 japaneast 僅支援
#         2018-09-01-preview / 2019-06-01 / 2020-05-01 / 2020-06-01-preview，
#         使用 2023-01-01（那是 assessmentProjects 的版本）會回傳
#         400 NoRegisteredProviderFound，故此處固定 2020-05-01。
#
#   部署前請確認訂閱已註冊 Provider：
#     az provider register --namespace Microsoft.Migrate --wait
#     az provider register --namespace Microsoft.OffAzure --wait
############################################
resource "azapi_resource" "migrate_project" {
  type      = "Microsoft.Migrate/migrateProjects@2020-05-01"
  name      = local.name.migrate_project
  location  = local.migrate_rg_location
  parent_id = local.migrate_rg_id

  # 2020-05-01 的 schema 不支援 publicNetworkAccess，送空 properties 即可
  body = {
    properties = {}
  }

  tags = merge(local.migrate_tags, {
    ResourceType = "MigrateProject"
    Purpose      = "Assessment-And-Migration"
  })

  schema_validation_enabled = false
}

############################################
# 【遷移工具層 / AzureMigrateRG】Key Vault
#   對應入口網站：Migrate-CRM5539kv（金鑰保存庫）
#   現況沒有 Private Endpoint，故預設允許公用網路存取。
############################################
resource "azurerm_key_vault" "migrate" {
  name                = local.name.migrate_kv
  location            = local.migrate_rg_location
  resource_group_name = local.migrate_rg_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = var.migrate_key_vault_sku

  rbac_authorization_enabled    = true
  purge_protection_enabled      = var.migrate_key_vault_purge_protection_enabled
  soft_delete_retention_days    = 7
  public_network_access_enabled = var.migrate_key_vault_public_network_access_enabled

  network_acls {
    bypass         = "AzureServices"
    default_action = var.migrate_key_vault_public_network_access_enabled ? "Allow" : "Deny"
  }

  tags = merge(local.migrate_tags, {
    ResourceType = "KeyVault"
    Purpose      = "Migration-Secrets"
  })
}

############################################
# 【遷移工具層 / AzureMigrateRG】儲存體
#   對應入口網站：migratecrmlog（儲存體帳戶）
############################################
resource "azurerm_storage_account" "migrate" {
  name                          = local.name.migrate_storage
  resource_group_name           = local.migrate_rg_name
  location                      = local.migrate_rg_location
  account_tier                  = "Standard"
  account_replication_type      = var.migrate_storage_replication_type
  account_kind                  = "StorageV2"
  min_tls_version               = "TLS1_2"
  https_traffic_only_enabled    = true
  public_network_access_enabled = var.migrate_storage_public_network_access_enabled

  tags = merge(local.migrate_tags, {
    ResourceType = "StorageAccount"
    Service      = "Storage-Blob"
    Purpose      = "Migration-Logs"
  })
}

############################################
# 【ADF-RG】Private DNS Zone（名稱由 Azure Private Link 規範固定，不可加前綴）
#   對應入口網站：privatelink.datafactory.azure.net
#   Private DNS Zone 為全域資源，連結至 Spoke-VNET。
#
#   【修正】Private DNS Zone / VNet Link 最多 15 個標籤，
#   改用 local.dns_base_tags（最多 4 個）+ ResourceType / Service（共最多 6 個），
#   不再套用 local.adf_tags，避免 400 BadRequest（資源標籤無效）。
############################################
resource "azurerm_private_dns_zone" "datafactory" {
  name                = "privatelink.datafactory.azure.net"
  resource_group_name = local.adf_rg_name

  tags = merge(local.dns_base_tags, {
    ResourceType = "PrivateDnsZone"
    Service      = "DataFactory"
  })
}

resource "azurerm_private_dns_zone_virtual_network_link" "datafactory_spoke" {
  name                  = "${local.prefix}link-spoke-vnet"
  resource_group_name   = local.adf_rg_name
  private_dns_zone_name = azurerm_private_dns_zone.datafactory.name
  virtual_network_id    = azurerm_virtual_network.spoke.id
  registration_enabled  = false

  tags = merge(local.dns_base_tags, {
    ResourceType = "PrivateDnsZoneLink"
  })
}

############################################
# 【ADF-RG】Data Factory
#   對應入口網站：adfsyscom（資料處理站 V2）
############################################
resource "azurerm_data_factory" "adf" {
  name                   = local.name.adf
  location               = local.adf_rg_location
  resource_group_name    = local.adf_rg_name
  public_network_enabled = var.adf_public_network_enabled

  identity {
    type = "SystemAssigned"
  }

  tags = merge(local.adf_tags, {
    ResourceType = "DataFactory"
  })
}

############################################
# 【ADF-RG】Key Vault
#   對應入口網站：kv-gfs-shir-yxqvj（金鑰保存庫）
############################################
resource "azurerm_key_vault" "adf" {
  name                = local.name.adf_kv
  location            = local.adf_rg_location
  resource_group_name = local.adf_rg_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = var.adf_key_vault_sku

  rbac_authorization_enabled    = true
  purge_protection_enabled      = false
  soft_delete_retention_days    = 7
  public_network_access_enabled = var.adf_key_vault_public_network_access_enabled

  network_acls {
    bypass         = "AzureServices"
    default_action = var.adf_key_vault_public_network_access_enabled ? "Allow" : "Deny"
  }

  tags = merge(local.adf_tags, {
    ResourceType = "KeyVault"
    Purpose      = "SHIR-Secrets"
  })
}

############################################
# 【ADF-RG】儲存體（啟用階層命名空間，支援 blob 與 dfs 兩個 Private Endpoint）
#   對應入口網站：jgfsshir01（儲存體帳戶）
############################################
resource "azurerm_storage_account" "adf" {
  name                          = local.name.adf_storage
  resource_group_name           = local.adf_rg_name
  location                      = local.adf_rg_location
  account_tier                  = "Standard"
  account_replication_type      = var.adf_storage_replication_type
  account_kind                  = "StorageV2"
  is_hns_enabled                = true
  min_tls_version               = "TLS1_2"
  https_traffic_only_enabled    = true
  public_network_access_enabled = false

  tags = merge(local.adf_tags, {
    ResourceType = "StorageAccount"
    Service      = "Storage-DataLake"
  })
}

############################################
# 【ADF-RG】Private Endpoint（皆佈署於 Spoke-VNET 的 PrivateEndpoint-Subnet）
#   對應入口網站：adf-pe / pe-jgfsshir01-blob / pe-jgfsshir01-dfs / pe-kv-gfs-shir
#   NIC 由 Private Endpoint 自動產生；adf-pe 的 NIC 在現況為自訂名稱 adf-pe-nic。
#   現況只有 privatelink.datafactory.azure.net 一個 DNS 區域，
#   因此僅 adf-pe 綁定 DNS 區域群組。
############################################
resource "azurerm_private_endpoint" "adf" {
  name                          = local.name.adf_pe
  location                      = local.adf_rg_location
  resource_group_name           = local.adf_rg_name
  subnet_id                     = azurerm_subnet.pe.id
  custom_network_interface_name = local.name.adf_pe_nic

  tags = merge(local.adf_tags, {
    ResourceType = "PrivateEndpoint"
    Service      = "DataFactory"
  })

  private_service_connection {
    name                           = "${local.prefix}adf-pe-connection"
    private_connection_resource_id = azurerm_data_factory.adf.id
    subresource_names              = ["dataFactory"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "${local.prefix}datafactory-private-dns"
    private_dns_zone_ids = [azurerm_private_dns_zone.datafactory.id]
  }
}

resource "azurerm_private_endpoint" "adf_blob" {
  name                = local.name.adf_blob_pe
  location            = local.adf_rg_location
  resource_group_name = local.adf_rg_name
  subnet_id           = azurerm_subnet.pe.id

  tags = merge(local.adf_tags, {
    ResourceType = "PrivateEndpoint"
    Service      = "Storage-Blob"
  })

  private_service_connection {
    name                           = "${local.prefix}pe-${lower(var.adf_storage_name)}-blob-connection"
    private_connection_resource_id = azurerm_storage_account.adf.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }
}

resource "azurerm_private_endpoint" "adf_dfs" {
  name                = local.name.adf_dfs_pe
  location            = local.adf_rg_location
  resource_group_name = local.adf_rg_name
  subnet_id           = azurerm_subnet.pe.id

  tags = merge(local.adf_tags, {
    ResourceType = "PrivateEndpoint"
    Service      = "Storage-DataLake"
  })

  private_service_connection {
    name                           = "${local.prefix}pe-${lower(var.adf_storage_name)}-dfs-connection"
    private_connection_resource_id = azurerm_storage_account.adf.id
    subresource_names              = ["dfs"]
    is_manual_connection           = false
  }
}

resource "azurerm_private_endpoint" "adf_kv" {
  name                = local.name.adf_kv_pe
  location            = local.adf_rg_location
  resource_group_name = local.adf_rg_name
  subnet_id           = azurerm_subnet.pe.id

  tags = merge(local.adf_tags, {
    ResourceType = "PrivateEndpoint"
    Service      = "KeyVault"
  })

  private_service_connection {
    name                           = "${local.prefix}pe-${var.adf_key_vault_name}-connection"
    private_connection_resource_id = azurerm_key_vault.adf.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }
}

############################################
# 【ADF-RG】Network Security Group
#   對應入口網站：ADF-NSF（入口網站顯示的現況名稱，原樣保留）
############################################
resource "azurerm_network_security_group" "adf" {
  name                = local.name.adf_nsg
  location            = local.adf_rg_location
  resource_group_name = local.adf_rg_name

  tags = merge(local.adf_tags, {
    ResourceType = "NetworkSecurityGroup"
    Service      = "DataFactory"
  })

  security_rule {
    name                       = "Allow-HTTPS-Inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Deny-Internet-Inbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}
