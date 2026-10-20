# ==========================================
# Azure Landing Zone Management Group 建立腳本
# ==========================================

# ===== 參數設定 =====
$ALZMG = "ALZ"
$APMG = "APGroup"
$InfraMG = "InfraGroup"

$WorkloadSubName = "Workload subscription"
$ConnectivitySubName = "Connectivity subscription"

# ==========================================
# 建立 Management Group (若不存在)
# ==========================================

function New-MGIfNotExists {
    param(
        [string]$GroupId,
        [string]$DisplayName,
        [string]$ParentId = $null
    )

    $existingMG = Get-AzManagementGroup -GroupName $GroupId -ErrorAction SilentlyContinue

    if ($null -eq $existingMG)
    {
        Write-Host "建立 Management Group : $GroupId"

        if ($ParentId)
        {
            New-AzManagementGroup `
                -GroupId $GroupId `
                -DisplayName $DisplayName `
                -ParentId $ParentId
        }
        else
        {
            New-AzManagementGroup `
                -GroupId $GroupId `
                -DisplayName $DisplayName
        }
    }
    else
    {
        Write-Host "$GroupId 已存在"
    }
}

# ==========================================
# 建立 ALZ
# ==========================================

New-MGIfNotExists `
    -GroupId $ALZMG `
    -DisplayName $ALZMG

# ==========================================
# 建立 APGroup
# ==========================================

New-MGIfNotExists `
    -GroupId $APMG `
    -DisplayName $APMG `
    -ParentId "/providers/Microsoft.Management/managementGroups/$ALZMG"

# ==========================================
# 建立 InfraGroup
# ==========================================

New-MGIfNotExists `
    -GroupId $InfraMG `
    -DisplayName $InfraMG `
    -ParentId "/providers/Microsoft.Management/managementGroups/$ALZMG"

# ==========================================
# 取得訂閱
# ==========================================

$WorkloadSub = Get-AzSubscription `
    | Where-Object {$_.Name -eq $WorkloadSubName}

$ConnectivitySub = Get-AzSubscription `
    | Where-Object {$_.Name -eq $ConnectivitySubName}

# ==========================================
# 移動 Workload Subscription
# ==========================================

if ($WorkloadSub)
{
    Write-Host "移動 Workload Subscription"

    New-AzManagementGroupSubscription `
        -GroupId $APMG `
        -SubscriptionId $WorkloadSub.Id
}
else
{
    Write-Warning "找不到 Workload subscription"
}

# ==========================================
# 移動 Connectivity Subscription
# ==========================================

if ($ConnectivitySub)
{
    Write-Host "移動 Connectivity Subscription"

    New-AzManagementGroupSubscription `
        -GroupId $InfraMG `
        -SubscriptionId $ConnectivitySub.Id
}
else
{
    Write-Warning "找不到 Connectivity subscription"
}

Write-Host ""
Write-Host "==================================="
Write-Host "ALZ 架構建立完成"
Write-Host "==================================="
