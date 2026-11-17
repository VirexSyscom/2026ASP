# ==========================================
# Azure Landing Zone Management Group 建立腳本
# 適用：Azure DevOps AzurePowerShell Task（已自動登入）
# ==========================================
$ErrorActionPreference = "Stop"

# ===== Management Group ID（不可包含空白） =====
$ALZMG   = "ALZ"
$APMG    = "APGroup"
$InfraMG = "InfraGroup"

# ===== Management Group 顯示名稱（可包含空白） =====
$ALZMGDisplayName   = "ALZ"
$APMGDisplayName    = "AP Group"
$InfraMGDisplayName = "Infra Group"

# ===== Subscription 顯示名稱 =====
$WorkloadSubName     = "Workload subscription"
$ConnectivitySubName = "Connectivity subscription"

# ==========================================
# 建立 Management Group（若不存在）
# ==========================================
function New-MGIfNotExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$GroupId,

        [Parameter(Mandatory = $true)]
        [string]$DisplayName,

        [string]$ParentId = $null
    )

    if ($GroupId -notmatch '^[A-Za-z0-9_.()-]+$') {
        throw "Management Group ID '$GroupId' 包含無效字元。僅允許英文字母、數字、-、_、(、)、.，且不可包含空白。"
    }

    $existingMG = Get-AzManagementGroup `
        -GroupName $GroupId `
        -ErrorAction SilentlyContinue

    if ($null -eq $existingMG) {
        Write-Host "建立 Management Group：$DisplayName [$GroupId]"

        $parameters = @{
            GroupName   = $GroupId
            DisplayName = $DisplayName
        }

        if ($ParentId) {
            $parameters.ParentId = $ParentId
        }

        New-AzManagementGroup @parameters | Out-Null
    }
    else {
        Write-Host "Management Group 已存在：$($existingMG.DisplayName) [$GroupId]"

        if ($existingMG.DisplayName -ne $DisplayName) {
            Write-Host "更新顯示名稱：$($existingMG.DisplayName) -> $DisplayName"
            Update-AzManagementGroup `
                -GroupName $GroupId `
                -DisplayName $DisplayName | Out-Null
        }
    }
}

# ==========================================
# 建立 Management Group 階層
# ==========================================
New-MGIfNotExists `
    -GroupId $ALZMG `
    -DisplayName $ALZMGDisplayName

$ALZParentId = "/providers/Microsoft.Management/managementGroups/$ALZMG"

New-MGIfNotExists `
    -GroupId $APMG `
    -DisplayName $APMGDisplayName `
    -ParentId $ALZParentId

New-MGIfNotExists `
    -GroupId $InfraMG `
    -DisplayName $InfraMGDisplayName `
    -ParentId $ALZParentId

# ==========================================
# 取得訂閱
# ==========================================
$WorkloadSubs = @(
    Get-AzSubscription | Where-Object { $_.Name -eq $WorkloadSubName }
)

$ConnectivitySubs = @(
    Get-AzSubscription | Where-Object { $_.Name -eq $ConnectivitySubName }
)

if ($WorkloadSubs.Count -gt 1) {
    throw "找到多個名稱為 '$WorkloadSubName' 的訂閱，請改用 Subscription ID 指定。"
}

if ($ConnectivitySubs.Count -gt 1) {
    throw "找到多個名稱為 '$ConnectivitySubName' 的訂閱，請改用 Subscription ID 指定。"
}

$WorkloadSub = $WorkloadSubs | Select-Object -First 1
$ConnectivitySub = $ConnectivitySubs | Select-Object -First 1

# ==========================================
# 移動 Workload Subscription 至 AP Group
# ==========================================
if ($WorkloadSub) {
    Write-Host "移動 Workload Subscription：$($WorkloadSub.Name) [$($WorkloadSub.Id)] -> $APMGDisplayName [$APMG]"
    New-AzManagementGroupSubscription `
        -GroupName $APMG `
        -SubscriptionId $WorkloadSub.Id | Out-Null
}
else {
    Write-Warning "找不到訂閱：$WorkloadSubName"
}

# ==========================================
# 移動 Connectivity Subscription 至 Infra Group
# ==========================================
if ($ConnectivitySub) {
    Write-Host "移動 Connectivity Subscription：$($ConnectivitySub.Name) [$($ConnectivitySub.Id)] -> $InfraMGDisplayName [$InfraMG]"
    New-AzManagementGroupSubscription `
        -GroupName $InfraMG `
        -SubscriptionId $ConnectivitySub.Id | Out-Null
}
else {
    Write-Warning "找不到訂閱：$ConnectivitySubName"
}

# ==========================================
# 驗證結果
# ==========================================
Write-Host ""
Write-Host "目前 ALZ Management Group 階層："
Get-AzManagementGroup `
    -GroupName $ALZMG `
    -Expand `
    -Recurse | Format-List

Write-Host ""
Write-Host "==================================="
Write-Host "ALZ 架構建立完成"
Write-Host "==================================="
