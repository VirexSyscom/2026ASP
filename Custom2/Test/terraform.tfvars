# Azure SQL Managed Instance（保留原始需求）
location                    = "japaneast"
crm_resource_group_name     = "Spoke-CRM-RG"
network_resource_group_name = "Spoke-Network-RG"

mi_name = "mssqlservermi221u81289"
managed_database_names = [
  "CRMData",
  "testCRMData",
]

# 真實 Azure Arc SQL Server 的目標值；資源由 Agent/Extension 探索，不由 AzAPI 偽造。
arc_machine_name      = "CRM-DB"
arc_sql_license_type  = "LicenseOnly"
arc_sql_database_names = [
  "CRMData",
  "master",
  "model",
  "msdb",
  "tempdb",
]

# 不要把密碼或 Service Principal secret 寫在此檔。
# Azure DevOps secret variables：
# - TF_VAR_sql_administrator_password
# - ARC_SP_CLIENT_ID
# - ARC_SP_CLIENT_SECRET
# - ARC_TENANT_ID
