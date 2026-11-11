# 圖片對齊值：名稱不加前綴、不加亂數後綴。
location                    = "japaneast"
crm_resource_group_name     = "Spoke-CRM-RG"
network_resource_group_name = "Spoke-Network-RG"

mi_name = "mssqlservermi221u81289"
managed_database_names = [
  "CRMData",
  "testCRMData",
]

arc_machine_name = "CRM-DB"
arc_sql_database_names = [
  "CRMData",
  "master",
  "model",
  "msdb",
  "tempdb",
]

# 不要把密碼寫在此檔；請在 Azure DevOps 建立 secret variable：
# TF_VAR_sql_administrator_password
