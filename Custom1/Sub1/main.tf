############################################
# main.tf
#   Spoke 網路 + PROD HR + UAT HR + 遷移工具層（AzureMigrateRG）
#
#   統一格式：
#     1. 命名一律經由 local.name 統一表，套用 local.prefix 前綴
#     2. 標籤一律以 merge(local.<層>_tags, { ResourceType = ... }) 產生
#     3. 四個資源群組獨立保留：Spoke 網路 / PROD HR / UAT HR / AzureMigrateRG
#        RG 名稱一律不套用前綴，但標籤一律套用
#     4. 每個 RG 皆支援 create_<層>_resource_group 切換「新建 / 沿用既有」
#     5. 遷移層不另建 VNet，一律沿用既有的 PROD Spoke-VNET
############################################

data "azurerm_client_config" "current" {}

locals {
  # 前綴：留空時不加分隔符號，例如 name_prefix = "demo" -> "demo-"
  prefix = var.name_prefix == "" ? "" : "${var.name_prefix}${var.name_separator}"

  # 供不允許連字號的資源（SQL Server、Storage、Compute Gallery）使用的緊湊前綴
  prefix_compact = lower(replace(var.name_prefix, "-", ""))

  # ---------- 統一命名表 ----------
  name = {
    # ===== Spoke 網路層 =====
    spoke_vnet       = "${local.prefix}Spoke-VNET"
    uat_spoke_vnet   = "${local.prefix}UAT-Spoke-VNET"
    ap_subnet        = "${local.prefix}AP-Subnet"
    db_subnet        = "${local.prefix}DB-Subnet"
    pe_subnet        = "${local.prefix}PrivateEndpoint-Subnet"
    uat_subnet       = "${local.prefix}Workload-Subnet"
    uat_pe_subnet    = "${local.prefix}UAT-PrivateEndpoint-Subnet"
    migrate_subnet   = "${local.prefix}Migrate-Subnet"
    bastion_subnet   = "AzureBastionSubnet" # Azure 保留名稱，不可加前綴
    ap_nsg           = "${local.prefix}AP-Subnet-NSG"
    db_nsg           = "${local.prefix}DB-Subnet-NSG"
    nat_pip          = "${local.prefix}nat-pip-${var.location_short}"
    nat_gateway      = "${local.prefix}SpokeHRNatGW"
    bastion          = "${local.prefix}Spoke-VNET-bastion"
    alert_nsg_write  = "${local.prefix}Create or Update Network Security Group Alert"
    alert_nsg_delete = "${local.prefix}Delete Network Security Group Alert"

    # ===== PROD HR 工作負載層 =====
    vm_identity     = "${local.prefix}vm-user-mid"
    lb_pip          = "${local.prefix}pip-hr-ap-${var.location_short}"
    lb              = "${local.prefix}hrap-lb"
    lb_frontend     = "${local.prefix}public-frontend"
    lb_backend_pool = "${local.prefix}hr-backend-pool"
    lb_probe        = "${local.prefix}https-probe"
    lb_rule         = "${local.prefix}https-rule"
    nic_ipconfig    = "${local.prefix}ipconfig1"
    sql_server      = "${local.prefix_compact}cmhrsrv${random_string.sql_suffix.result}"
    sql_database    = "${local.prefix}hrdata"
    sql_pe          = "${local.prefix}cmhrsrv-pe"
    compute_gallery = "${local.prefix_compact}cmgallery"
    shared_image    = "${local.prefix}hr-vm"
    ag_email        = "${local.prefix}email-alert"
    ag_vm           = "${local.prefix}vm-actiongroup"
    alert_sql_dtu   = "${local.prefix}dtu-percentage"

    # ===== UAT HR 工作負載層 =====
    uat_vm             = "${local.prefix}${var.uat_vm_name}"
    uat_nic_primary    = "${local.prefix}${var.uat_vm_name}-nic01"
    uat_nic_secondary  = "${local.prefix}${var.uat_vm_name}-nic02"
    uat_os_disk        = "${local.prefix}${var.uat_vm_name}-osdisk"
    uat_data_disk      = "${local.prefix}${var.uat_vm_name}-datadisk01"
    uat_sql_server     = "${local.prefix_compact}uatcmhrsrv${random_string.uat_sql_suffix.result}"
    uat_sql_database   = "${local.prefix}uat-hrdata"
    uat_sql_pe         = "${local.prefix}uat-cmhrsrv-pe"
    uat_storage        = "${local.prefix_compact}uatsyscom${random_string.uat_storage_suffix.result}"
    uat_storage_pe     = "${local.prefix}uat-syscom-blob-pe"
    uat_eventgrid      = "${local.prefix}uat-syscom-topic"
    uat_ag_vm          = "${local.prefix}uat-vm-actiongroup"
    uat_alert_vm_avail = "${local.prefix}uat-vm-availability"

    # ===== 遷移工具層（AzureMigrateRG）=====
    # 對應入口網站清單：
    #   discovervmware4949vault / Migrate-HR / Migrate-HR8786kv
    #   migratelog / migratelog-<guid> / SQLtoAzureSQL
    migrate_project   = "${local.prefix}${var.migrate_project_name}"
    recovery_vault    = "${local.prefix}${var.recovery_vault_name}${random_string.migrate_suffix.result}vault"
    migrate_kv        = substr("${local.prefix_compact}${var.migrate_key_vault_name}${random_string.migrate_suffix.result}kv", 0, 24)
    migrate_storage   = substr("${local.prefix_compact}${lower(var.migrate_storage_name)}${random_string.migrate_suffix.result}", 0, 24)
    migrate_kv_pe     = "${local.prefix}${var.migrate_key_vault_name}-kv-pe"
    migrate_blob_pe   = "${local.prefix}${var.migrate_storage_name}-blob-pe"
    migrate_eventgrid = "${local.prefix}${var.migrate_storage_name}-topic"
    dms               = "${local.prefix}${var.database_migration_service_name}"
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
  hr_tags      = merge(local.common_tags, { Layer = "Workload", Workload = "HR" }, var.hr_tags)

  # UAT 網路資源：沿用 Spoke 網路標籤但改寫 Environment
  uat_tags = merge(local.network_tags, { Environment = "uat" })

  # UAT HR 工作負載：沿用 HR 標籤但改寫 Environment
  uat_hr_tags = merge(local.hr_tags, { Environment = "uat" }, var.uat_hr_tags)

  # 遷移工具層
  migrate_tags = merge(local.common_tags, { Layer = "Migration", Workload = "AzureMigrate" }, var.migrate_tags)

  # ---------- 資源群組解析 ----------
  network_rg_name     = var.create_network_resource_group ? azurerm_resource_group.network[0].name : data.azurerm_resource_group.network_existing[0].name
  network_rg_location = var.create_network_resource_group ? azurerm_resource_group.network[0].location : data.azurerm_resource_group.network_existing[0].location

  hr_rg_name     = var.create_hr_resource_group ? azurerm_resource_group.hr[0].name : data.azurerm_resource_group.hr_existing[0].name
  hr_rg_location = var.create_hr_resource_group ? azurerm_resource_group.hr[0].location : data.azurerm_resource_group.hr_existing[0].location

  uat_hr_rg_name     = var.create_uat_hr_resource_group ? azurerm_resource_group.uat_hr[0].name : data.azurerm_resource_group.uat_hr_existing[0].name
  uat_hr_rg_location = var.create_uat_hr_resource_group ? azurerm_resource_group.uat_hr[0].location : data.azurerm_resource_group.uat_hr_existing[0].location

  migrate_rg_name     = var.create_migrate_resource_group ? azurerm_resource_group.migrate[0].name : data.azurerm_resource_group.migrate_existing[0].name
  migrate_rg_location = var.create_migrate_resource_group ? azurerm_resource_group.migrate[0].location : data.azurerm_resource_group.migrate_existing[0].location
  migrate_rg_id       = var.create_migrate_resource_group ? azurerm_resource_group.migrate[0].id : data.azurerm_resource_group.migrate_existing[0].id

  subscription_id = data.azurerm_client_config.current.subscription_id
  alert_scope     = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"

  # 網路活動記錄警示：未指定 Action Group 時，沿用 PROD HR 的 Email Action Group
  effective_alert_action_group_id = var.alert_action_group_id != "" ? var.alert_action_group_id : azurerm_monitor_action_group.email.id

}

############################################
# 全域唯一名稱用亂數後綴
############################################
resource "random_string" "sql_suffix" {
  length  = 4
  upper   = false
  special = false

  keepers = {
    prefix = local.prefix
  }
}

resource "random_string" "uat_sql_suffix" {
  length  = 4
  upper   = false
  special = false

  keepers = {
    prefix = local.prefix
  }
}

resource "random_string" "uat_storage_suffix" {
  length  = 4
  upper   = false
  special = false

  keepers = {
    prefix = local.prefix
  }
}

# 遷移層共用後綴（RSV / Key Vault / Storage 皆需全域唯一）
resource "random_string" "migrate_suffix" {
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
#   2. PROD HR     var.hr_resource_group_name
#   3. UAT  HR     var.uat_hr_resource_group_name
#   4. 遷移工具    var.migrate_resource_group_name（AzureMigrateRG）
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

data "azurerm_resource_group" "hr_existing" {
  count = var.create_hr_resource_group ? 0 : 1
  name  = var.hr_resource_group_name
}

resource "azurerm_resource_group" "hr" {
  count    = var.create_hr_resource_group ? 1 : 0
  name     = var.hr_resource_group_name
  location = var.location

  tags = merge(local.hr_tags, {
    ResourceType = "ResourceGroup"
  })
}

data "azurerm_resource_group" "uat_hr_existing" {
  count = var.create_uat_hr_resource_group ? 0 : 1
  name  = var.uat_hr_resource_group_name
}

resource "azurerm_resource_group" "uat_hr" {
  count    = var.create_uat_hr_resource_group ? 1 : 0
  name     = var.uat_hr_resource_group_name
  location = var.location

  tags = merge(local.uat_hr_tags, {
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

############################################
# 【Spoke 網路】Virtual Network - Spoke-VNET（正式環境）
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

resource "azurerm_subnet" "db" {
  name                 = local.name.db_subnet
  resource_group_name  = local.network_rg_name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [var.db_subnet_prefix]
}

resource "azurerm_subnet" "pe" {
  name                              = local.name.pe_subnet
  resource_group_name               = local.network_rg_name
  virtual_network_name              = azurerm_virtual_network.spoke.name
  address_prefixes                  = [var.pe_subnet_prefix]
  private_endpoint_network_policies = "Disabled"
}

############################################
# 【Spoke 網路】Migrate-Subnet
#   Database Migration Service 需專屬委派子網路，
#   建立在既有的 PROD Spoke-VNET，不另建 VNet。
############################################
resource "azurerm_subnet" "migrate" {
  count                = var.create_database_migration_service ? 1 : 0
  name                 = local.name.migrate_subnet
  resource_group_name  = local.network_rg_name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [var.migrate_subnet_prefix]
}

# Bastion 專用子網路，名稱為 Azure 保留字，不可加前綴
# Developer SKU 不需要 AzureBastionSubnet，故為條件式建立
resource "azurerm_subnet" "bastion" {
  count                = var.create_bastion_subnet ? 1 : 0
  name                 = local.name.bastion_subnet
  resource_group_name  = local.network_rg_name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [var.bastion_subnet_prefix]
}

############################################
# 【Spoke 網路】Virtual Network - UAT-Spoke-VNET（測試環境）
############################################
resource "azurerm_virtual_network" "uat_spoke" {
  name                = local.name.uat_spoke_vnet
  location            = local.network_rg_location
  resource_group_name = local.network_rg_name
  address_space       = var.uat_spoke_vnet_address_space

  tags = merge(local.uat_tags, {
    ResourceType = "VirtualNetwork"
    Workload     = "UAT"
  })
}

resource "azurerm_subnet" "uat_workload" {
  name                 = local.name.uat_subnet
  resource_group_name  = local.network_rg_name
  virtual_network_name = azurerm_virtual_network.uat_spoke.name
  address_prefixes     = [var.uat_workload_subnet_prefix]
}

resource "azurerm_subnet" "uat_pe" {
  name                              = local.name.uat_pe_subnet
  resource_group_name               = local.network_rg_name
  virtual_network_name              = azurerm_virtual_network.uat_spoke.name
  address_prefixes                  = [var.uat_pe_subnet_prefix]
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

resource "azurerm_network_security_group" "db" {
  name                = local.name.db_nsg
  location            = local.network_rg_location
  resource_group_name = local.network_rg_name

  tags = merge(local.network_tags, {
    ResourceType = "NetworkSecurityGroup"
    SubnetTier   = "Database"
  })

  # 允許 AP Subnet 連 SQL
  security_rule {
    name                       = "Allow-SQL-From-AP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "1433"
    source_address_prefix      = var.ap_subnet_prefix
    destination_address_prefix = "*"
  }

  # 允許 Migrate-Subnet（DMS）連 SQL
  security_rule {
    name                       = "Allow-SQL-From-Migrate"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "1433"
    source_address_prefix      = var.migrate_subnet_prefix
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Deny-All-Inbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "ap" {
  subnet_id                 = azurerm_subnet.ap.id
  network_security_group_id = azurerm_network_security_group.ap.id
}

resource "azurerm_subnet_network_security_group_association" "db" {
  subnet_id                 = azurerm_subnet.db.id
  network_security_group_id = azurerm_network_security_group.db.id
}

############################################
# 【Spoke 網路】NAT Gateway
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

resource "azurerm_subnet_nat_gateway_association" "db" {
  subnet_id      = azurerm_subnet.db.id
  nat_gateway_id = azurerm_nat_gateway.spoke.id
}

# DMS 需對外連線 Azure 服務端點，沿用同一組 NAT Gateway 出口
resource "azurerm_subnet_nat_gateway_association" "migrate" {
  count          = var.create_database_migration_service ? 1 : 0
  subnet_id      = azurerm_subnet.migrate[0].id
  nat_gateway_id = azurerm_nat_gateway.spoke.id
}

############################################
# 【Spoke 網路】Bastion（Developer SKU：無公用 IP）
############################################
resource "azurerm_bastion_host" "spoke" {
  name                = local.name.bastion
  location            = local.network_rg_location
  resource_group_name = local.network_rg_name
  sku                 = var.bastion_sku

  virtual_network_id = azurerm_virtual_network.spoke.id
  copy_paste_enabled = true

  tags = merge(local.network_tags, {
    ResourceType = "Bastion"
    Purpose      = "SecureRemoteAccess"
    AccessModel  = "NoPublicIP-Developer"
    Scope        = "SpokeVNetOnly"
  })
}

############################################
# 【Spoke 網路】Private DNS Zone
#   名稱由 Azure Private Link 規範固定，絕對不可加前綴
#   PROD / UAT VNet 皆連結至同一組 Zone，
#   遷移層的 Key Vault / Storage PE 也共用這些 Zone。
############################################
resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = local.network_rg_name

  tags = merge(local.network_tags, {
    ResourceType = "PrivateDnsZone"
    Service      = "Storage-Blob"
  })
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob_spoke" {
  name                  = "${local.prefix}link-spoke-vnet"
  resource_group_name   = local.network_rg_name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = azurerm_virtual_network.spoke.id
  registration_enabled  = false

  tags = merge(local.network_tags, {
    ResourceType = "PrivateDnsZoneLink"
  })
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob_uat" {
  name                  = "${local.prefix}link-uat-spoke-vnet"
  resource_group_name   = local.network_rg_name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = azurerm_virtual_network.uat_spoke.id
  registration_enabled  = false

  tags = merge(local.uat_tags, {
    ResourceType = "PrivateDnsZoneLink"
  })
}

resource "azurerm_private_dns_zone" "sql" {
  name                = "privatelink.database.windows.net"
  resource_group_name = local.network_rg_name

  tags = merge(local.network_tags, {
    ResourceType = "PrivateDnsZone"
    Service      = "Azure-SQL"
  })
}

resource "azurerm_private_dns_zone_virtual_network_link" "sql_spoke" {
  name                  = "${local.prefix}link-spoke-vnet"
  resource_group_name   = local.network_rg_name
  private_dns_zone_name = azurerm_private_dns_zone.sql.name
  virtual_network_id    = azurerm_virtual_network.spoke.id
  registration_enabled  = false

  tags = merge(local.network_tags, {
    ResourceType = "PrivateDnsZoneLink"
  })
}

resource "azurerm_private_dns_zone_virtual_network_link" "sql_uat" {
  name                  = "${local.prefix}link-uat-spoke-vnet"
  resource_group_name   = local.network_rg_name
  private_dns_zone_name = azurerm_private_dns_zone.sql.name
  virtual_network_id    = azurerm_virtual_network.uat_spoke.id
  registration_enabled  = false

  tags = merge(local.uat_tags, {
    ResourceType = "PrivateDnsZoneLink"
  })
}

# 遷移層 Key Vault Private Endpoint 專用 Zone（同樣置於 Spoke 網路 RG）
resource "azurerm_private_dns_zone" "keyvault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = local.network_rg_name

  tags = merge(local.network_tags, {
    ResourceType = "PrivateDnsZone"
    Service      = "KeyVault"
  })
}

resource "azurerm_private_dns_zone_virtual_network_link" "keyvault_spoke" {
  name                  = "${local.prefix}link-spoke-vnet"
  resource_group_name   = local.network_rg_name
  private_dns_zone_name = azurerm_private_dns_zone.keyvault.name
  virtual_network_id    = azurerm_virtual_network.spoke.id
  registration_enabled  = false

  tags = merge(local.network_tags, {
    ResourceType = "PrivateDnsZoneLink"
  })
}

############################################
# 【Spoke 網路】Activity Log Alert（location 固定 global）
############################################
resource "azurerm_monitor_activity_log_alert" "nsg_write" {
  name                = local.name.alert_nsg_write
  resource_group_name = local.network_rg_name
  location            = "global"
  scopes              = [local.alert_scope]
  description         = "當 NSG 被建立或更新時觸發"
  enabled             = true

  tags = merge(local.network_tags, {
    ResourceType = "ActivityLogAlert"
    Purpose      = "Security-Monitoring"
  })

  criteria {
    category       = "Administrative"
    operation_name = "Microsoft.Network/networkSecurityGroups/write"
    level          = "Informational"
  }

  action {
    action_group_id = local.effective_alert_action_group_id
  }
}

resource "azurerm_monitor_activity_log_alert" "nsg_delete" {
  name                = local.name.alert_nsg_delete
  resource_group_name = local.network_rg_name
  location            = "global"
  scopes              = [local.alert_scope]
  description         = "當 NSG 被刪除時觸發"
  enabled             = true

  tags = merge(local.network_tags, {
    ResourceType = "ActivityLogAlert"
    Purpose      = "Security-Monitoring"
  })

  criteria {
    category       = "Administrative"
    operation_name = "Microsoft.Network/networkSecurityGroups/delete"
    level          = "Informational"
  }

  action {
    action_group_id = local.effective_alert_action_group_id
  }
}

############################################
# 【PROD HR】受控識別
############################################
resource "azurerm_user_assigned_identity" "vm" {
  name                = local.name.vm_identity
  location            = local.hr_rg_location
  resource_group_name = local.hr_rg_name

  tags = merge(local.hr_tags, {
    ResourceType = "ManagedIdentity"
  })
}

############################################
# 【PROD HR】Load Balancer
############################################
resource "azurerm_public_ip" "lb" {
  name                = local.name.lb_pip
  location            = local.hr_rg_location
  resource_group_name = local.hr_rg_name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = merge(local.hr_tags, {
    ResourceType = "PublicIP"
    Purpose      = "LoadBalancer-Frontend"
  })
}

resource "azurerm_lb" "hr" {
  name                = local.name.lb
  location            = local.hr_rg_location
  resource_group_name = local.hr_rg_name
  sku                 = "Standard"

  tags = merge(local.hr_tags, {
    ResourceType = "LoadBalancer"
    SubnetTier   = "Application"
  })

  frontend_ip_configuration {
    name                 = local.name.lb_frontend
    public_ip_address_id = azurerm_public_ip.lb.id
  }
}

resource "azurerm_lb_backend_address_pool" "hr" {
  name            = local.name.lb_backend_pool
  loadbalancer_id = azurerm_lb.hr.id
}

resource "azurerm_lb_probe" "https" {
  name            = local.name.lb_probe
  loadbalancer_id = azurerm_lb.hr.id
  protocol        = "Tcp"
  port            = 443
}

resource "azurerm_lb_rule" "https" {
  name                           = local.name.lb_rule
  loadbalancer_id                = azurerm_lb.hr.id
  protocol                       = "Tcp"
  frontend_port                  = 443
  backend_port                   = 443
  frontend_ip_configuration_name = local.name.lb_frontend
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.hr.id]
  probe_id                       = azurerm_lb_probe.https.id
  disable_outbound_snat          = true
}

############################################
# 【PROD HR】虛擬機器（掛載本組態建立的 AP-Subnet）
############################################
resource "azurerm_network_interface" "vm" {
  for_each = var.vm_names

  name                = "${local.prefix}${each.value}-nic"
  location            = local.hr_rg_location
  resource_group_name = local.hr_rg_name

  tags = merge(local.hr_tags, {
    ResourceType = "NetworkInterface"
  })

  ip_configuration {
    name                          = local.name.nic_ipconfig
    subnet_id                     = azurerm_subnet.ap.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface_backend_address_pool_association" "vm" {
  for_each = var.vm_names

  network_interface_id    = azurerm_network_interface.vm[each.value].id
  ip_configuration_name   = local.name.nic_ipconfig
  backend_address_pool_id = azurerm_lb_backend_address_pool.hr.id
}

resource "azurerm_windows_virtual_machine" "vm" {
  for_each = var.vm_names

  name                  = "${local.prefix}${each.value}"
  computer_name         = substr(replace("${local.prefix}${each.value}", "-", ""), 0, 15)
  location              = local.hr_rg_location
  resource_group_name   = local.hr_rg_name
  size                  = var.vm_size
  admin_username        = var.admin_username
  admin_password        = var.admin_password
  network_interface_ids = [azurerm_network_interface.vm[each.value].id]

  tags = merge(local.hr_tags, {
    ResourceType = "VirtualMachine"
    SubnetTier   = "Application"
  })

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.vm.id]
  }

  os_disk {
    name                 = "${local.prefix}${each.value}-osdisk"
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
# 【PROD HR】Azure SQL + Private Endpoint
############################################
resource "azurerm_mssql_server" "hr" {
  name                          = local.name.sql_server
  resource_group_name           = local.hr_rg_name
  location                      = local.hr_rg_location
  version                       = "12.0"
  administrator_login           = var.sql_administrator_login
  administrator_login_password  = var.sql_administrator_password
  minimum_tls_version           = "1.2"
  public_network_access_enabled = false

  tags = merge(local.hr_tags, {
    ResourceType = "SqlServer"
    SubnetTier   = "Database"
  })
}

resource "azurerm_mssql_database" "hr" {
  name        = local.name.sql_database
  server_id   = azurerm_mssql_server.hr.id
  sku_name    = var.sql_database_sku
  max_size_gb = var.sql_database_max_size_gb

  tags = merge(local.hr_tags, {
    ResourceType = "SqlDatabase"
    SubnetTier   = "Database"
  })
}

resource "azurerm_private_endpoint" "sql" {
  name                = local.name.sql_pe
  location            = local.hr_rg_location
  resource_group_name = local.hr_rg_name
  subnet_id           = azurerm_subnet.pe.id

  tags = merge(local.hr_tags, {
    ResourceType = "PrivateEndpoint"
    Service      = "Azure-SQL"
  })

  private_service_connection {
    name                           = "${local.prefix}cmhrsrv-connection"
    private_connection_resource_id = azurerm_mssql_server.hr.id
    subresource_names              = ["sqlServer"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "${local.prefix}sql-private-dns"
    private_dns_zone_ids = [azurerm_private_dns_zone.sql.id]
  }
}

############################################
# 【PROD HR】Compute Gallery
############################################
resource "azurerm_shared_image_gallery" "hr" {
  name                = local.name.compute_gallery
  resource_group_name = local.hr_rg_name
  location            = local.hr_rg_location
  description         = "HR VM image gallery"

  tags = merge(local.hr_tags, {
    ResourceType = "ComputeGallery"
  })
}

resource "azurerm_shared_image" "hr" {
  name                = local.name.shared_image
  gallery_name        = azurerm_shared_image_gallery.hr.name
  resource_group_name = local.hr_rg_name
  location            = local.hr_rg_location
  os_type             = "Windows"
  hyper_v_generation  = "V2"

  tags = merge(local.hr_tags, {
    ResourceType = "SharedImage"
  })

  identifier {
    publisher = "CM"
    offer     = "HR"
    sku       = "HR-VM"
  }
}

############################################
# 【PROD HR】監控
############################################
resource "azurerm_monitor_action_group" "email" {
  name                = local.name.ag_email
  resource_group_name = local.hr_rg_name
  short_name          = substr("${local.prefix_compact}Email", 0, 12)

  tags = merge(local.hr_tags, {
    ResourceType = "ActionGroup"
    Purpose      = "Email-Notification"
  })

  email_receiver {
    name          = "operations"
    email_address = var.alert_email
  }
}

resource "azurerm_monitor_action_group" "vm" {
  name                = local.name.ag_vm
  resource_group_name = local.hr_rg_name
  short_name          = substr("${local.prefix_compact}VM", 0, 12)

  tags = merge(local.hr_tags, {
    ResourceType = "ActionGroup"
    Purpose      = "VM-Notification"
  })

  email_receiver {
    name          = "operations"
    email_address = var.alert_email
  }
}

resource "azurerm_monitor_metric_alert" "cpu" {
  for_each = azurerm_windows_virtual_machine.vm

  name                = "${local.prefix}cpu-${each.key}"
  resource_group_name = local.hr_rg_name
  scopes              = [each.value.id]
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  tags = merge(local.hr_tags, {
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

  action {
    action_group_id = azurerm_monitor_action_group.vm.id
  }
}

resource "azurerm_monitor_metric_alert" "sql_dtu" {
  name                = local.name.alert_sql_dtu
  resource_group_name = local.hr_rg_name
  scopes              = [azurerm_mssql_database.hr.id]
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  tags = merge(local.hr_tags, {
    ResourceType = "MetricAlert"
    Purpose      = "Performance-Monitoring"
  })

  criteria {
    metric_namespace = "Microsoft.Sql/servers/databases"
    metric_name      = "dtu_consumption_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.dtu_alert_threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.email.id
  }
}

############################################
# 【UAT HR】虛擬機器（雙網卡，掛載 UAT-Spoke-VNET 的 Workload-Subnet）
############################################
resource "azurerm_network_interface" "uat_vm_primary" {
  name                = local.name.uat_nic_primary
  location            = local.uat_hr_rg_location
  resource_group_name = local.uat_hr_rg_name

  tags = merge(local.uat_hr_tags, {
    ResourceType = "NetworkInterface"
    Purpose      = "Primary"
  })

  ip_configuration {
    name                          = local.name.nic_ipconfig
    subnet_id                     = azurerm_subnet.uat_workload.id
    private_ip_address_allocation = "Dynamic"
    primary                       = true
  }
}

resource "azurerm_network_interface" "uat_vm_secondary" {
  name                = local.name.uat_nic_secondary
  location            = local.uat_hr_rg_location
  resource_group_name = local.uat_hr_rg_name

  tags = merge(local.uat_hr_tags, {
    ResourceType = "NetworkInterface"
    Purpose      = "Secondary"
  })

  ip_configuration {
    name                          = local.name.nic_ipconfig
    subnet_id                     = azurerm_subnet.uat_workload.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_windows_virtual_machine" "uat_vm" {
  name                = local.name.uat_vm
  computer_name       = substr(replace(local.name.uat_vm, "-", ""), 0, 15)
  location            = local.uat_hr_rg_location
  resource_group_name = local.uat_hr_rg_name
  size                = var.uat_vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password

  network_interface_ids = [
    azurerm_network_interface.uat_vm_primary.id,
    azurerm_network_interface.uat_vm_secondary.id
  ]

  tags = merge(local.uat_hr_tags, {
    ResourceType = "VirtualMachine"
    SubnetTier   = "Application"
  })

  os_disk {
    name                 = local.name.uat_os_disk
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

resource "azurerm_managed_disk" "uat_vm_data" {
  name                 = local.name.uat_data_disk
  location             = local.uat_hr_rg_location
  resource_group_name  = local.uat_hr_rg_name
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = var.uat_data_disk_size_gb

  tags = merge(local.uat_hr_tags, {
    ResourceType = "ManagedDisk"
  })
}

resource "azurerm_virtual_machine_data_disk_attachment" "uat_vm_data" {
  managed_disk_id    = azurerm_managed_disk.uat_vm_data.id
  virtual_machine_id = azurerm_windows_virtual_machine.uat_vm.id
  lun                = 1
  caching            = "ReadWrite"
}

############################################
# 【UAT HR】Azure SQL + Private Endpoint
############################################
resource "azurerm_mssql_server" "uat_hr" {
  name                          = local.name.uat_sql_server
  resource_group_name           = local.uat_hr_rg_name
  location                      = local.uat_hr_rg_location
  version                       = "12.0"
  administrator_login           = var.sql_administrator_login
  administrator_login_password  = var.sql_administrator_password
  minimum_tls_version           = "1.2"
  public_network_access_enabled = false

  tags = merge(local.uat_hr_tags, {
    ResourceType = "SqlServer"
    SubnetTier   = "Database"
  })
}

resource "azurerm_mssql_database" "uat_hr" {
  name        = local.name.uat_sql_database
  server_id   = azurerm_mssql_server.uat_hr.id
  sku_name    = var.uat_sql_database_sku
  max_size_gb = var.uat_sql_database_max_size_gb

  tags = merge(local.uat_hr_tags, {
    ResourceType = "SqlDatabase"
    SubnetTier   = "Database"
  })
}

resource "azurerm_private_endpoint" "uat_sql" {
  name                = local.name.uat_sql_pe
  location            = local.uat_hr_rg_location
  resource_group_name = local.uat_hr_rg_name
  subnet_id           = azurerm_subnet.uat_pe.id

  tags = merge(local.uat_hr_tags, {
    ResourceType = "PrivateEndpoint"
    Service      = "Azure-SQL"
  })

  private_service_connection {
    name                           = "${local.prefix}uat-cmhrsrv-connection"
    private_connection_resource_id = azurerm_mssql_server.uat_hr.id
    subresource_names              = ["sqlServer"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "${local.prefix}uat-sql-private-dns"
    private_dns_zone_ids = [azurerm_private_dns_zone.sql.id]
  }
}

############################################
# 【UAT HR】儲存體 + Private Endpoint + Event Grid
############################################
resource "azurerm_storage_account" "uat" {
  name                          = local.name.uat_storage
  resource_group_name           = local.uat_hr_rg_name
  location                      = local.uat_hr_rg_location
  account_tier                  = "Standard"
  account_replication_type      = var.storage_replication_type
  min_tls_version               = "TLS1_2"
  public_network_access_enabled = false

  tags = merge(local.uat_hr_tags, {
    ResourceType = "StorageAccount"
    Service      = "Storage-Blob"
  })
}

resource "azurerm_private_endpoint" "uat_storage_blob" {
  name                = local.name.uat_storage_pe
  location            = local.uat_hr_rg_location
  resource_group_name = local.uat_hr_rg_name
  subnet_id           = azurerm_subnet.uat_pe.id

  tags = merge(local.uat_hr_tags, {
    ResourceType = "PrivateEndpoint"
    Service      = "Storage-Blob"
  })

  private_service_connection {
    name                           = "${local.prefix}uat-syscom-blob-connection"
    private_connection_resource_id = azurerm_storage_account.uat.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "${local.prefix}uat-blob-private-dns"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }
}

resource "azurerm_eventgrid_system_topic" "uat_storage" {
  count = var.create_uat_eventgrid_system_topic ? 1 : 0

  name                   = local.name.uat_eventgrid
  resource_group_name    = local.uat_hr_rg_name
  location               = local.uat_hr_rg_location
  source_arm_resource_id = azurerm_storage_account.uat.id
  topic_type             = "Microsoft.Storage.StorageAccounts"

  tags = merge(local.uat_hr_tags, {
    ResourceType = "EventGridSystemTopic"
    Service      = "Storage-Events"
  })
}

############################################
# 【UAT HR】監控
############################################
resource "azurerm_monitor_action_group" "uat_vm" {
  name                = local.name.uat_ag_vm
  resource_group_name = local.uat_hr_rg_name
  short_name          = substr("${local.prefix_compact}UATVM", 0, 12)

  tags = merge(local.uat_hr_tags, {
    ResourceType = "ActionGroup"
    Purpose      = "VM-Notification"
  })

  email_receiver {
    name          = "operations"
    email_address = var.alert_email
  }
}

resource "azurerm_monitor_metric_alert" "uat_vm_availability" {
  name                = local.name.uat_alert_vm_avail
  resource_group_name = local.uat_hr_rg_name
  scopes              = [azurerm_windows_virtual_machine.uat_vm.id]
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"

  tags = merge(local.uat_hr_tags, {
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

  action {
    action_group_id = azurerm_monitor_action_group.uat_vm.id
  }
}

resource "azurerm_monitor_metric_alert" "uat_sql_dtu" {
  name                = "${local.prefix}uat-dtu-percentage"
  resource_group_name = local.uat_hr_rg_name
  scopes              = [azurerm_mssql_database.uat_hr.id]
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  tags = merge(local.uat_hr_tags, {
    ResourceType = "MetricAlert"
    Purpose      = "Performance-Monitoring"
  })

  criteria {
    metric_namespace = "Microsoft.Sql/servers/databases"
    metric_name      = "dtu_consumption_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.dtu_alert_threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.uat_vm.id
  }
}

############################################
# 【遷移工具層 / AzureMigrateRG】復原服務保存庫
#   對應入口網站：discovervmware4949vault（復原服務保存庫）
#   供 Azure Migrate 的 VMware 探索與伺服器移轉使用
############################################
resource "azurerm_recovery_services_vault" "migrate" {
  name                = local.name.recovery_vault
  location            = local.migrate_rg_location
  resource_group_name = local.migrate_rg_name
  sku                 = var.recovery_vault_sku
  storage_mode_type   = var.recovery_vault_storage_mode
  soft_delete_enabled = var.recovery_vault_soft_delete_enabled

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
#   對應入口網站：Migrate-HR（Azure Migrate）
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
#     az provider register --namespace Microsoft.DataMigration --wait
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
# 【遷移工具層 / AzureMigrateRG】Key Vault + Private Endpoint
#   對應入口網站：Migrate-HR8786kv（金鑰保存庫）
#   供 Azure Migrate / DMS 保存移轉憑證與連線字串
############################################
resource "azurerm_key_vault" "migrate" {
  name                = local.name.migrate_kv
  location            = local.migrate_rg_location
  resource_group_name = local.migrate_rg_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = var.migrate_key_vault_sku

  enable_rbac_authorization     = true
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

resource "azurerm_private_endpoint" "migrate_kv" {
  count               = var.migrate_key_vault_public_network_access_enabled ? 0 : 1
  name                = local.name.migrate_kv_pe
  location            = local.migrate_rg_location
  resource_group_name = local.migrate_rg_name

  # 沿用原本的 PROD Spoke-VNET PrivateEndpoint-Subnet
  subnet_id = azurerm_subnet.pe.id

  tags = merge(local.migrate_tags, {
    ResourceType = "PrivateEndpoint"
    Service      = "KeyVault"
  })

  private_service_connection {
    name                           = "${local.prefix}migrate-kv-connection"
    private_connection_resource_id = azurerm_key_vault.migrate.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "${local.prefix}migrate-kv-private-dns"
    private_dns_zone_ids = [azurerm_private_dns_zone.keyvault.id]
  }
}

############################################
# 【遷移工具層 / AzureMigrateRG】儲存體 + Private Endpoint + Event Grid
#   對應入口網站：
#     migratelog（儲存體帳戶）
#     migratelog-<guid>（事件方格系統主題）
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

resource "azurerm_private_endpoint" "migrate_blob" {
  count               = var.migrate_storage_public_network_access_enabled ? 0 : 1
  name                = local.name.migrate_blob_pe
  location            = local.migrate_rg_location
  resource_group_name = local.migrate_rg_name

  # 沿用原本的 PROD Spoke-VNET PrivateEndpoint-Subnet
  subnet_id = azurerm_subnet.pe.id

  tags = merge(local.migrate_tags, {
    ResourceType = "PrivateEndpoint"
    Service      = "Storage-Blob"
  })

  private_service_connection {
    name                           = "${local.prefix}migrate-blob-connection"
    private_connection_resource_id = azurerm_storage_account.migrate.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "${local.prefix}migrate-blob-private-dns"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }
}

resource "azurerm_eventgrid_system_topic" "migrate_storage" {
  count = var.create_migrate_eventgrid_system_topic ? 1 : 0

  name                   = local.name.migrate_eventgrid
  resource_group_name    = local.migrate_rg_name
  location               = local.migrate_rg_location
  source_arm_resource_id = azurerm_storage_account.migrate.id
  topic_type             = "Microsoft.Storage.StorageAccounts"

  identity {
    type = "SystemAssigned"
  }

  tags = merge(local.migrate_tags, {
    ResourceType = "EventGridSystemTopic"
    Service      = "Storage-Events"
  })
}

############################################
# 【遷移工具層 / AzureMigrateRG】Database Migration Service
#   對應入口網站：SQLtoAzureSQL（Azure Database Migration Service）
#   1. DMS 必須掛在既有 VNet 的專屬子網路（此處為 Spoke-VNET/Migrate-Subnet）
#   2. 傳統版 DMS（Microsoft.DataMigration/services）已宣告淘汰，
#      新建移轉專案建議改用 Azure SQL 移轉延伸模組；此處保留以對齊現況資源。
############################################
resource "azurerm_database_migration_service" "sql_to_azure_sql" {
  count               = var.create_database_migration_service ? 1 : 0
  name                = local.name.dms
  location            = local.migrate_rg_location
  resource_group_name = local.migrate_rg_name
  subnet_id           = azurerm_subnet.migrate[0].id
  sku_name            = var.database_migration_service_sku

  tags = merge(local.migrate_tags, {
    ResourceType = "DatabaseMigrationService"
    Purpose      = "SQL-To-AzureSQL"
  })

  depends_on = [azurerm_subnet_nat_gateway_association.migrate]
}

############################################
# 【遷移工具層】權限指派
#   讓 RSV 的系統受控識別能寫入遷移記錄儲存體。
#
#   注意：Azure DevOps 服務連線的 SPN 通常僅具 Contributor，
#         不含 Microsoft.Authorization/roleAssignments/write，
#         直接建立會出現 403 AuthorizationFailed，故預設關閉
#         （var.create_migrate_role_assignment = false）。
#
#   關閉時請由具權限的管理員手動指派一次：
#     az role assignment create \
#       --assignee-object-id <RSV 的 principalId> \
#       --assignee-principal-type ServicePrincipal \
#       --role "Storage Blob Data Contributor" \
#       --scope <遷移儲存體帳戶的資源 ID>
############################################
resource "azurerm_role_assignment" "vault_to_migrate_storage" {
  count                = var.create_migrate_role_assignment ? 1 : 0
  scope                = azurerm_storage_account.migrate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_recovery_services_vault.migrate.identity[0].principal_id
}
