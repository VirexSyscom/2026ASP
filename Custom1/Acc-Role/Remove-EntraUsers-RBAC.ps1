<#
.SYNOPSIS
  刪除先前建立的 10 個 Entra ID 帳號，並先移除其 Azure RBAC 角色指派（可在 Azure DevOps AzurePowerShell@5 Task 中執行）。

.NOTES
  執行身分需要：
    1) Microsoft Graph 應用程式權限：User.ReadWrite.All (需 Admin Consent)，或 Entra 角色「User Administrator」
       (若要 -PermanentDelete 永久刪除，可能需要 User.DeleteRestore.All 或 Directory.ReadWrite.All)
    2) Azure RBAC：目標範圍上的 Owner 或 User Access Administrator (用來移除角色指派)
  只會處理下方清單內的 UPN，不會動到其他帳號。
  可重複執行：帳號不存在或角色已移除則略過。
  -DryRun $true 只列出將執行的動作，不實際刪除。
#>
[CmdletBinding()]
param(
    [bool]$DryRun          = $false,   # $true = 只預覽，不實際刪除
    [bool]$PermanentDelete = $false,   # $true = 刪除後再從資源回收筒永久刪除 (否則保留 30 天可還原)
    [bool]$RemoveRoles     = $true,    # 刪除帳號前，先移除其 RBAC 角色指派

    [string]$WorkloadSubscription     = 'Workload',
    [string]$ConnectivitySubscription = 'Connectivity',
    [string]$AlzMgName   = 'ALZ',
    [string]$ApMgName    = 'APGroup',
    [string]$InfraMgName = 'InfraGroup'
)

$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------
# 0. 前置檢查
# ------------------------------------------------------------
foreach ($m in 'Az.Accounts', 'Az.Resources') {
    if (-not (Get-Module -ListAvailable -Name $m)) { throw "找不到模組 $m，請先安裝 Az 模組。" }
}
Import-Module Az.Accounts, Az.Resources -ErrorAction Stop

$ctx = Get-AzContext
if (-not $ctx) {
    throw '目前沒有 Azure 登入內容。請在 Azure DevOps 使用 AzurePowerShell@5 Task (含 azureSubscription) 執行，或先 Connect-AzAccount -UseDeviceAuthentication。'
}
Write-Host "目前身分: $($ctx.Account.Id) | Tenant: $($ctx.Tenant.Id)" -ForegroundColor Cyan
if ($DryRun) { Write-Host '*** DryRun 模式：不會實際刪除任何資料 ***' -ForegroundColor Magenta }

# ------------------------------------------------------------
# 1. 輔助函式
# ------------------------------------------------------------
function Get-GraphHeaders {
    $t = (Get-AzAccessToken -ResourceUrl 'https://graph.microsoft.com' -ErrorAction Stop).Token
    if ($t -is [System.Security.SecureString]) { $t = ConvertFrom-SecureString -SecureString $t -AsPlainText }
    return @{ Authorization = "Bearer $t"; 'Content-Type' = 'application/json' }
}

function Get-StatusCode($err) {
    try { return [int]$err.Exception.Response.StatusCode } catch { return 0 }
}

function Get-EntraUser([string]$Upn) {
    $enc = [uri]::EscapeDataString($Upn)
    try {
        return Invoke-RestMethod -Method Get -Headers (Get-GraphHeaders) `
               -Uri ('https://graph.microsoft.com/v1.0/users/{0}?$select=id,userPrincipalName,displayName' -f $enc)
    }
    catch {
        if ((Get-StatusCode $_) -eq 404) { return $null }
        throw "查詢使用者 $Upn 失敗: $($_.ErrorDetails.Message)"
    }
}

$allSubs = @(Get-AzSubscription -TenantId $ctx.Tenant.Id -ErrorAction Stop)

function Resolve-Subscription([string]$Key) {
    $hit = $allSubs | Where-Object { $_.Id -eq $Key -or $_.Name -eq $Key }
    if (-not $hit) { $hit = $allSubs | Where-Object { $_.Name -like "*$Key*" } }
    if (-not $hit)           { throw "找不到訂閱: $Key (可見訂閱: $($allSubs.Name -join ', '))" }
    if (@($hit).Count -gt 1) { throw "訂閱關鍵字 '$Key' 符合多個: $(@($hit).Name -join ', ')，請改用完整名稱或訂閱 ID。" }
    return $hit
}

function Resolve-MgScope([string]$Name) {
    $mg = Get-AzManagementGroup -GroupName $Name -ErrorAction SilentlyContinue
    if (-not $mg) {
        $mg = Get-AzManagementGroup -ErrorAction Stop | Where-Object { $_.DisplayName -eq $Name } | Select-Object -First 1
    }
    if (-not $mg) { return $null }
    return $mg.Id
}

function Resolve-RgScope {
    param([string]$RgName, [string]$PreferredSubId)
    $ordered = @()
    if ($PreferredSubId) { $ordered += $allSubs | Where-Object { $_.Id -eq $PreferredSubId } }
    $ordered += $allSubs | Where-Object { $_.Id -ne $PreferredSubId }
    foreach ($s in $ordered) {
        $c  = Set-AzContext -SubscriptionId $s.Id -TenantId $ctx.Tenant.Id
        $rg = Get-AzResourceGroup -Name $RgName -DefaultProfile $c -ErrorAction SilentlyContinue
        if ($rg) { return $rg.ResourceId }
    }
    return $null
}

$workloadSub     = Resolve-Subscription $WorkloadSubscription
$connectivitySub = Resolve-Subscription $ConnectivitySubscription

# ------------------------------------------------------------
# 2. 要刪除的帳號清單 (與建立腳本一致，UPN 原樣保留)
# ------------------------------------------------------------
$targets = @(
    @{ Upn='Workload_Sub_Contributer@ai365.com.tw';     Role='Contributor'; Type='Sub'; Target=$workloadSub.Id }
    @{ Upn='Connectivity_Sub_Contributer@ai365.com.tw'; Role='Contributor'; Type='Sub'; Target=$connectivitySub.Id }

    @{ Upn='ALZMG_Owenr@ai365.com.tw';   Role='Owner'; Type='MG'; Target=$AlzMgName }
    @{ Upn='APMG_Owenr@ai365.com.tw';    Role='Owner'; Type='MG'; Target=$ApMgName }
    @{ Upn='InfraMG_Owenr@ai365.com.tw'; Role='Owner'; Type='MG'; Target=$InfraMgName }

    @{ Upn='Spoke_HR_RG_Ower@ai365.com.tw';       Role='Owner'; Type='RG'; Target='Spoke-HR-RG';      Hint=$workloadSub.Id }
    @{ Upn='UAT_Spoke_HR_RG_Ower@ai365.com.tw';   Role='Owner'; Type='RG'; Target='UAT-Spoke-HR-RG';  Hint=$workloadSub.Id }
    @{ Upn='AzureMigrateRG_Owenr@ai365.com.tw';   Role='Owner'; Type='RG'; Target='AzureMigrateRG';   Hint=$workloadSub.Id }
    @{ Upn='Spoke_Network_RG_Owenr@ai365.com.tw'; Role='Owner'; Type='RG'; Target='Spoke-Network-RG'; Hint=$workloadSub.Id }
    @{ Upn='Hub_Network_RG_Owner@ai365.com.tw';   Role='Owner'; Type='RG'; Target='Hub-Network-RG';   Hint=$connectivitySub.Id }
)

# ------------------------------------------------------------
# 3. 執行
# ------------------------------------------------------------
$results = New-Object System.Collections.Generic.List[object]

foreach ($t in $targets) {
    Write-Host "`n=== $($t.Upn)" -ForegroundColor Cyan
    $status = 'OK'
    try {
        $user = Get-EntraUser -Upn $t.Upn
        if (-not $user) {
            Write-Host '  [略過] 帳號不存在 (可能已刪除)' -ForegroundColor Yellow
            $status = 'Not found'
        }
        else {
            # --- (a) 移除 RBAC 角色指派 ---
            if ($RemoveRoles) {
                $scope = switch ($t.Type) {
                    'Sub' { "/subscriptions/$($t.Target)" }
                    'MG'  { Resolve-MgScope $t.Target }
                    'RG'  { Resolve-RgScope -RgName $t.Target -PreferredSubId $t.Hint }
                }
                if (-not $scope) {
                    Write-Host "  [警告] 找不到範圍 ($($t.Type): $($t.Target))，略過移除角色指派" -ForegroundColor DarkYellow
                }
                else {
                    $ras = @(Get-AzRoleAssignment -ObjectId $user.id -Scope $scope -ErrorAction SilentlyContinue |
                             Where-Object { $_.Scope -eq $scope })
                    foreach ($ra in $ras) {
                        if ($DryRun) { Write-Host "  [DryRun] 將移除角色 $($ra.RoleDefinitionName) @ $scope" }
                        else {
                            Remove-AzRoleAssignment -ObjectId $user.id -RoleDefinitionName $ra.RoleDefinitionName -Scope $scope -ErrorAction Stop | Out-Null
                            Write-Host "  [已移除角色] $($ra.RoleDefinitionName) @ $scope" -ForegroundColor Green
                        }
                    }
                    if ($ras.Count -eq 0) { Write-Host '  [略過] 此範圍沒有該帳號的角色指派' -ForegroundColor Yellow }
                }
            }

            # --- (b) 刪除 Entra 帳號 ---
            if ($DryRun) {
                Write-Host "  [DryRun] 將刪除帳號 $($t.Upn) ($($user.id))"
                $status = 'DryRun'
            }
            else {
                Invoke-RestMethod -Method Delete -Headers (Get-GraphHeaders) `
                    -Uri "https://graph.microsoft.com/v1.0/users/$($user.id)" | Out-Null
                Write-Host "  [已刪除] $($t.Upn) (保留於資源回收筒 30 天，可還原)" -ForegroundColor Green

                # --- (c) 選用：永久刪除 ---
                if ($PermanentDelete) {
                    $done = $false
                    for ($i = 1; $i -le 6 -and -not $done; $i++) {
                        try {
                            Invoke-RestMethod -Method Delete -Headers (Get-GraphHeaders) `
                                -Uri "https://graph.microsoft.com/v1.0/directory/deletedItems/$($user.id)" | Out-Null
                            $done = $true
                            Write-Host '  [已永久刪除]' -ForegroundColor Green
                            $status = 'Permanently deleted'
                        }
                        catch {
                            if ((Get-StatusCode $_) -eq 404) { Write-Host "  等待帳號進入回收筒… ($i/6)" -ForegroundColor DarkYellow; Start-Sleep -Seconds 10 }
                            else { throw "永久刪除失敗: $($_.ErrorDetails.Message)" }
                        }
                    }
                    if (-not $done) { throw '永久刪除逾時，帳號仍在回收筒中。' }
                }
                else { $status = 'Deleted (soft)' }
            }
        }
    }
    catch {
        $status = "FAILED: $($_.Exception.Message)"
        Write-Host "  [失敗] $($_.Exception.Message)" -ForegroundColor Red
    }
    $results.Add([pscustomobject]@{ UPN=$t.Upn; Status=$status })
}

# ------------------------------------------------------------
# 4. 結果彙總
# ------------------------------------------------------------
Write-Host "`n================ 執行結果 ================" -ForegroundColor Cyan
$results | Format-Table -AutoSize -Wrap | Out-String -Width 250 | Write-Host

$failed = @($results | Where-Object { $_.Status -like 'FAILED*' })
if ($failed.Count -gt 0) {
    Write-Host "##vso[task.logissue type=error]有 $($failed.Count) 筆失敗，請檢視上方輸出。"
    exit 1
}
Write-Host '全部完成。' -ForegroundColor Green
