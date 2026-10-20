# ALZ Management Groups Terraform

## 目標架構

```text
Tenant Root Group
├── ALZ
│   ├── APGroup
│   │   └── Workload subscription
│   └── InfraGroup
│       └── Connectivity subscription
└── Open AI-02 Azure subscription
```

## 使用方式

1. 複製變數範例：

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. 將 `terraform.tfvars` 內的 Tenant ID 與三個 Subscription ID 改成實際值。

3. 執行：

   ```bash
   terraform init
   terraform fmt -recursive
   terraform validate
   terraform plan -out=tfplan
   terraform apply tfplan
   ```

## Azure DevOps 建議

不要把正式 `terraform.tfvars` 提交到 Git。可將下列值設為秘密變數，並透過 `TF_VAR_` 環境變數傳入：

- `TF_VAR_tenant_id`
- `TF_VAR_provider_subscription_id`
- `TF_VAR_connectivity_subscription_id`
- `TF_VAR_workload_subscription_id`
- `TF_VAR_open_ai_subscription_id`

Service Connection 使用的 Service Principal 必須有權建立／移動管理群組，並有權將三個訂閱移動到指定的管理群組。

## 既有管理群組

若 ALZ、APGroup 或 InfraGroup 已由 Portal 建立，請先匯入 State，不要直接重複建立：

```bash
terraform import azurerm_management_group.alz \
  /providers/Microsoft.Management/managementGroups/alz

terraform import azurerm_management_group.ap_group \
  /providers/Microsoft.Management/managementGroups/apgroup

terraform import azurerm_management_group.infra_group \
  /providers/Microsoft.Management/managementGroups/infragroup
```

若實際管理群組 ID 不是 `alz`、`apgroup`、`infragroup`，請替換成 Azure Portal 顯示的管理群組 ID。
