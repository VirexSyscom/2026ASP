############################################
# terraform.tfvars
############################################
# subscription_id 通常由 Azure DevOps Service Connection 注入。
# subscription_id = "00000000-0000-0000-0000-000000000000"

location    = "japaneast"
name_prefix = "demo"

network_resource_group_name   = "Spoke-Network-RG"
create_network_resource_group = true
crm_resource_group_name       = "Spoke-CRM-RG"
create_crm_resource_group     = true

vnet_name        = "Spoke-VNET"
mi_subnet_name   = "MI-Subnet"
vnet_address_space = ["10.10.0.0/16"]
mi_subnet_prefix = "10.10.2.0/24"

# Managed Instance 名稱是全域 DNS 名稱，必須為小寫且唯一；Terraform 會自動
# 加上 name_prefix 與 6 碼亂數後綴。使用者資料庫名稱固定保持為 CRMData。
managed_instance_name_base = "crmdata-mi"
crm_database_name          = "CRMData"

sql_administrator_login = "crmadminuser"
# 未提供密碼時 Terraform 會產生 24 碼密碼並保存於遠端 state。
# 若需覆寫，請在 Pipeline 的 plan/apply 工作明確將秘密變數映射成
# TF_VAR_sql_administrator_password；不要把密碼寫入此檔。

mi_sku_name           = "GP_Gen5"
mi_vcores             = 4
mi_storage_size_in_gb = 32
mi_license_type       = "LicenseIncluded"
timezone_id           = "UTC"

tags = {
  Environment = "prod"
  Application = "CRM"
  ManagedBy   = "Terraform"
  DataClass   = "Confidential"
}
