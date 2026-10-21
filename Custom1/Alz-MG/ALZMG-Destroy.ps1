# ==========================================================
# 移除 ALZ 架構：將 ALZ 底下所有訂閱移回 Tenant Root Group，
# 再由最底層開始刪除 ALZ / InfraGroup / APGroup
# 適用：Azure DevOps AzurePowerShell Task（已自動登入，請勿 Connect-AzAccount）
# ==========================================================

$ErrorActionPreference = "Stop"

# ---------- 參數 ----------
$ALZMG = "ALZ"     # ALZ 最上層管理群組 ID

# ---------- 方法 1：Tenant Root Group ID = Tenant ID ----------
Write-Host "取得 Tenant Root Group"
$TenantRootGroup = (Get-AzContext).Tenant.Id

if (:IsNullOrWhiteSpace($TenantRootGroup)) {
    throw "無法從 Get-AzContext 取得 Tenant ID，請確認 Service Connection 登入狀態"
}

Write-Host "Tenant Root Group = $TenantRootGroup"

# 檢查是否看得到 Root Group（僅警告，不中止）
$rootCheck = Get-AzManagementGroup -GroupName $TenantRootGroup -ErrorAction SilentlyContinue
if (-not $rootCheck) {
    Write-Warning "目前身分看不到 Tenant Root Group，若後續移動訂閱失敗，請在 Tenant Root Group 的 IAM 授予 Management Group Contributor 或 Owner"
}

# ---------- 函式：遞迴取得 MG 底下所有訂閱 ----------
function Get-AllChildSubscriptions {
    param($Node)
    $result = @()
    foreach ($child in $Node.Children) {
        if ($child.Type -like "*subscriptions") {
            # 訂閱的 Name 即為 Subscription ID
            $result += [pscustomobject]@{
                Id   = $child.Name
                Name = $child.DisplayName
            }
        }
        elseif ($child.Children) {
            $result += Get-AllChildSubscriptions -Node $child
        }
    }
    return $result
}

# ---------- 函式：遞迴刪除 MG（由最底層開始） ----------
function Remove-MGTree {
    param([string]$GroupName)

    $mg = Get-AzManagementGroup -GroupName $GroupName -Expand -ErrorAction SilentlyContinue
    if (-not $mg) {
        Write-Host "管理群組 $GroupName 不存在，略過"
        return
    }

    foreach ($child in $mg.Children) {
        if ($child.Type -like "*managementGroups") {
            Remove-MGTree -GroupName $child.Name
        }
    }

    Write-Host "刪除管理群組：$GroupName"
    Remove-AzManagementGroup -GroupName $GroupName | Out-Null
}

# ==========================================================
# 步驟 1：取得 ALZ 底下所有訂閱
# ==========================================================
$alz = Get-AzManagementGroup -GroupName $ALZMG -Expand -Recurse -ErrorAction SilentlyContinue

if (-not $alz) {
    Write-Host "找不到管理群組 $ALZMG，無需處理"
    return
}

$subs = @(Get-AllChildSubscriptions -Node $alz)
Write-Host "ALZ 底下共找到 $($subs.Count) 個訂閱"

# ==========================================================
# 步驟 2：將訂閱移回 Tenant Root Group
# ==========================================================
foreach ($sub in $subs) {
    Write-Host "移動訂閱 [$($sub.Name)] ($($sub.Id)) 回 Tenant Root Group"
    New-AzManagementGroupSubscription `
        -GroupName $TenantRootGroup `
        -SubscriptionId $sub.Id | Out-Null
}

# 等待 Azure 同步
if ($subs.Count -gt 0) {
    Write-Host "等待 Azure 同步 (20 秒)..."
    Start-Sleep -Seconds 20
}

# ==========================================================
# 步驟 3：刪除 ALZ 管理群組樹（APGroup → InfraGroup → ALZ）
# ==========================================================
$maxRetry = 3
for ($i = 1; $i -le $maxRetry; $i++) {
    try {
        Remove-MGTree -GroupName $ALZMG
        break
    }
    catch {
        Write-Warning "第 $i 次刪除失敗：$($_.Exception.Message)"
        if ($i -eq $maxRetry) { throw }
        Start-Sleep -Seconds 20
    }
}

# ==========================================================
# 步驟 4：驗證結果
# ==========================================================
Write-Host "`n目前管理群組："
Get-AzManagementGroup | Select-Object Name, DisplayName | Format-Table

Write-Host "`nTenant Root Group 下的子項目："
(Get-AzManagementGroup -GroupName $TenantRootGroup -Expand -ErrorAction SilentlyContinue).Children |
    Select-Object DisplayName, Type | Format-Table

Write-Host "ALZ 架構移除完成"
