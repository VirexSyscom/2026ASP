# ==========================================
# 移除 ALZ 架構
# 將所有訂閱移回 Tenant Root Group
# ==========================================

# 不要在 Azure DevOps 中執行 Connect-AzAccount
# AzurePowerShell Task 已自動登入

# Subscription 名稱
$WorkloadSubName = "Workload subscription"
$ConnectivitySubName = "Connectivity subscription"

# Management Group
$ALZMG = "ALZ"
$APMG = "APGroup"
$InfraMG = "InfraGroup"

Write-Host "取得 Tenant Root Group"

$TenantRootGroup = (Get-AzManagementGroup).ParentName

if ([string]::IsNullOrEmpty($TenantRootGroup))
{
    $TenantRootGroup = (
        Get-AzManagementGroup |
        Where-Object { $_.DisplayName -like "*Tenant Root*" }
    ).Name
}

Write-Host "Tenant Root Group = $TenantRootGroup"

# ==========================================
# 取得 Subscription
# ==========================================

$WorkloadSub = Get-AzSubscription |
    Where-Object Name -eq $WorkloadSubName

$ConnectivitySub = Get-AzSubscription |
    Where-Object Name -eq $ConnectivitySubName

# ==========================================
# 移回 Tenant Root
# ==========================================

if ($WorkloadSub)
{
    Write-Host "移動 Workload Subscription 回 Tenant Root"

    New-AzManagementGroupSubscription `
        -GroupId $TenantRootGroup `
        -SubscriptionId $WorkloadSub.Id
}

if ($ConnectivitySub)
{
    Write-Host "移動 Connectivity Subscription 回 Tenant Root"

    New-AzManagementGroupSubscription `
        -GroupId $TenantRootGroup `
        -SubscriptionId $ConnectivitySub.Id
}

# 等待 Azure 同步
Start-Sleep -Seconds 15

# ==========================================
# 刪除 APGroup
# ==========================================

$APExist = Get-AzManagementGroup `
    -GroupName $APMG `
    -ErrorAction SilentlyContinue

if ($APExist)
{
    Write-Host "刪除 APGroup"

    Remove-AzManagementGroup `
        -GroupName $APMG
}

# ==========================================
# 刪除 InfraGroup
# ==========================================

$InfraExist = Get-AzManagementGroup `
    -GroupName $InfraMG `
    -ErrorAction SilentlyContinue

if ($InfraExist)
{
    Write-Host "刪除 InfraGroup"

    Remove-AzManagementGroup `
        -GroupName $InfraMG
}

# 等待同步

Start-Sleep -Seconds 10

# ==========================================
# 刪除 ALZ
# ==========================================

$ALZExist = Get-AzManagementGroup `
    -GroupName $ALZMG `
    -ErrorAction SilentlyContinue

if ($ALZExist)
{
    Write-Host "刪除 ALZ"

    Remove-AzManagementGroup `
        -GroupName $ALZMG
}

Write-Host ""
Write-Host "====================================="
Write-Host "ALZ 已移除"
Write-Host "所有訂閱已回到 Tenant Root Group"
Write-Host "====================================="
