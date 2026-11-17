<#
.SYNOPSIS
  刪除先前建立的 11 個 Entra ID 帳號，並先移除清單指定的 Azure RBAC 角色指派。
  可在 Azure DevOps AzurePowerShell@5 Task 中執行。
.NOTES
  執行身分需要：
    1) Microsoft Graph 應用程式權限 User.ReadWrite.All（需 Admin Consent），或 Entra 角色 User Administrator
       若要永久刪除，可能需要 User.DeleteRestore.All 或 Directory.ReadWrite.All
    2) Azure RBAC：目標範圍上的 Owner 或 User Access Administrator
  只處理下方清單內的 UPN。可重複執行；帳號不存在或指定角色已移除則略過。
#>
[CmdletBinding()]
param(
    [bool]$DryRun          = $false,
    [bool]$PermanentDelete = $false,
    [bool]$RemoveRoles     = $true,
    [string]$WorkloadSubscription     = 'Workload',
    [string]$ConnectivitySubscription = 'Connectivity',
    [string]$AlzMgName   = 'ALZ',
    [string]$ApMgName    = 'AP Group',
    [string]$InfraMgName = 'Infra Group'
)

$ErrorActionPreference = 'Stop'
foreach ($m in 'Az.Accounts', 'Az.Resources') {
    if (-not (Get-Module -ListAvailable -Name $m)) { throw "找不到模組 $m，請先安裝 Az 模組。" }
}
Import-Module Az.Accounts, Az.Resources -ErrorAction Stop

$originalContext = Get-AzContext
if (-not $originalContext) {
    throw '目前沒有 Azure 登入內容。請在 Azure DevOps 使用 AzurePowerShell@5 Task（含 azureSubscription）執行，或先 Connect-AzAccount -UseDeviceAuthentication。'
}
$ctx = $originalContext
Write-Host "目前身分: $($ctx.Account.Id) | Tenant: $($ctx.Tenant.Id)" -ForegroundColor Cyan
if ($DryRun) { Write-Host '*** DryRun 模式：不會實際刪除任何資料 ***' -ForegroundColor Magenta }

function Get-GraphHeaders {
    $t = (Get-AzAccessToken -ResourceUrl 'https://graph.microsoft.com' -ErrorAction Stop).Token
    if ($t -is [System.Security.SecureString]) { $t = ConvertFrom-SecureString -SecureString $t -AsPlainText }
    @{ Authorization = "Bearer $t"; 'Content-Type' = 'application/json' }
}
function Get-StatusCode($ErrorRecord) {
    try { [int]$ErrorRecord.Exception.Response.StatusCode } catch { 0 }
}
function Get-EntraUser([string]$Upn) {
    $enc = [uri]::EscapeDataString($Upn)
    try {
        Invoke-RestMethod -Method Get -Headers (Get-GraphHeaders) -Uri ('https://graph.microsoft.com/v1.0/users/{0}?$select=id,userPrincipalName,displayName' -f $enc)
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
    if (-not $hit) { throw "找不到訂閱: $Key（可見訂閱: $($allSubs.Name -join ', ')）" }
    if (@($hit).Count -gt 1) { throw "訂閱關鍵字 '$Key' 符合多個: $(@($hit).Name -join ', ')，請改用完整名稱或訂閱 ID。" }
    $hit
}
function Resolve-MgScope([string]$Name) {
    $mg = Get-AzManagementGroup -GroupName $Name -ErrorAction SilentlyContinue
    if (-not $mg) {
        $mg = Get-AzManagementGroup -ErrorAction Stop | Where-Object { $_.DisplayName -eq $Name } | Select-Object -First 1
    }
    if (-not $mg) { return $null }
    $mg.Id
}
function Resolve-RgScope {
    param([string]$RgName, [string]$PreferredSubId)
    $ordered = @()
    if ($PreferredSubId) { $ordered += $allSubs | Where-Object { $_.Id -eq $PreferredSubId } }
    $ordered += $allSubs | Where-Object { $_.Id -ne $PreferredSubId }
    foreach ($s in $ordered) {
        $c = Set-AzContext -SubscriptionId $s.Id -TenantId $ctx.Tenant.Id -Scope Process
        $rg = Get-AzResourceGroup -Name $RgName -DefaultProfile $c -ErrorAction SilentlyContinue
        if ($rg) { return $rg.ResourceId }
    }
    $null
}

$workloadSub = Resolve-Subscription $WorkloadSubscription
$connectivitySub = Resolve-Subscription $ConnectivitySubscription
$targets = @(
    @{ Upn='Workload_Sub_Contributor@ai365.com.tw'; Role='Contributor'; Type='Sub'; Target=$workloadSub.Id }
    @{ Upn='Connectivity_Sub_Contributor@ai365.com.tw'; Role='Contributor'; Type='Sub'; Target=$connectivitySub.Id }
    @{ Upn='ALZMG_Contributor@ai365.com.tw'; Role='Contributor'; Type='MG'; Target=$AlzMgName }
    @{ Upn='APMG_Contributor@ai365.com.tw'; Role='Contributor'; Type='MG'; Target=$ApMgName }
    @{ Upn='InfraMG_Contributor@ai365.com.tw'; Role='Contributor'; Type='MG'; Target=$InfraMgName }
    @{ Upn='Spoke_CRM_RG_Owner@ai365.com.tw'; Role='Owner'; Type='RG'; Target='Spoke-CRM-RG'; Hint=$workloadSub.Id }
    @{ Upn='ADF_RG_Owner@ai365.com.tw'; Role='Owner'; Type='RG'; Target='ADF-RG'; Hint=$workloadSub.Id }
    @{ Upn='AzureMigrateRG_Owner@ai365.com.tw'; Role='Owner'; Type='RG'; Target='AzureMigrateRG'; Hint=$workloadSub.Id }
    @{ Upn='Spoke_Network_RG_Owner@ai365.com.tw'; Role='Owner'; Type='RG'; Target='Spoke-Network-RG'; Hint=$workloadSub.Id }
    @{ Upn='Hub_Network_RG_Owner@ai365.com.tw'; Role='Owner'; Type='RG'; Target='Hub-Network-RG'; Hint=$connectivitySub.Id }
    @{ Upn='Hub_Mgmt_RG_Owner@ai365.com.tw'; Role='Owner'; Type='RG'; Target='Hub-Mgmt-RG'; Hint=$connectivitySub.Id }
)

$results = New-Object System.Collections.Generic.List[object]
try {
    foreach ($t in $targets) {
        Write-Host "`n=== $($t.Upn)" -ForegroundColor Cyan
        $status = 'OK'
        try {
            $user = Get-EntraUser -Upn $t.Upn
            if (-not $user) {
                Write-Host '  [略過] 帳號不存在（可能已刪除）' -ForegroundColor Yellow
                $status = 'Not found'
            }
            else {
                if ($RemoveRoles) {
                    $scope = switch ($t.Type) {
                        'Sub' { "/subscriptions/$($t.Target)" }
                        'MG'  { Resolve-MgScope $t.Target }
                        'RG'  { Resolve-RgScope -RgName $t.Target -PreferredSubId $t.Hint }
                        default { throw "不支援的範圍類型: $($t.Type)" }
                    }
                    if (-not $scope) {
                        Write-Host "  [警告] 找不到範圍（$($t.Type): $($t.Target)），略過移除角色指派" -ForegroundColor DarkYellow
                    }
                    else {
                        # 只移除清單中指定的角色，不移除該帳號在同一 Scope 的其他角色。
                        $ras = @(Get-AzRoleAssignment -ObjectId $user.id -Scope $scope -RoleDefinitionName $t.Role -ErrorAction SilentlyContinue |
                            Where-Object { $_.Scope -eq $scope -and $_.RoleDefinitionName -eq $t.Role })
                        foreach ($ra in $ras) {
                            if ($DryRun) {
                                Write-Host "  [DryRun] 將移除角色 $($ra.RoleDefinitionName) @ $scope"
                            }
                            else {
                                Remove-AzRoleAssignment -InputObject $ra -ErrorAction Stop
                                Write-Host "  [已移除角色] $($ra.RoleDefinitionName) @ $scope" -ForegroundColor Green
                            }
                        }
                        if ($ras.Count -eq 0) {
                            Write-Host "  [略過] 此範圍沒有該帳號的 $($t.Role) 角色指派" -ForegroundColor Yellow
                        }
                    }
                }

                if ($DryRun) {
                    Write-Host "  [DryRun] 將刪除帳號 $($t.Upn) ($($user.id))"
                    $status = 'DryRun'
                }
                else {
                    Invoke-RestMethod -Method Delete -Headers (Get-GraphHeaders) -Uri "https://graph.microsoft.com/v1.0/users/$($user.id)" | Out-Null
                    Write-Host "  [已刪除] $($t.Upn)（保留於資源回收筒 30 天，可還原）" -ForegroundColor Green
                    if ($PermanentDelete) {
                        $done = $false
                        # 最多等待約 180 秒，避免 Graph deletedItems 同步較慢造成假失敗。
                        for ($i = 1; $i -le 12 -and -not $done; $i++) {
                            try {
                                Invoke-RestMethod -Method Delete -Headers (Get-GraphHeaders) -Uri "https://graph.microsoft.com/v1.0/directory/deletedItems/$($user.id)" | Out-Null
                                $done = $true
                                $status = 'Permanently deleted'
                                Write-Host '  [已永久刪除]' -ForegroundColor Green
                            }
                            catch {
                                if ((Get-StatusCode $_) -eq 404) {
                                    Write-Host "  等待帳號進入回收筒... ($i/12)" -ForegroundColor DarkYellow
                                    Start-Sleep -Seconds 15
                                }
                                else { throw "永久刪除失敗: $($_.Exception.Message)" }
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
}
finally {
    if ($originalContext) {
        Set-AzContext -Context $originalContext -Scope Process -ErrorAction SilentlyContinue | Out-Null
    }
}

Write-Host "`n================ 執行結果 ================" -ForegroundColor Cyan
$results | Format-Table -AutoSize -Wrap | Out-String -Width 250 | Write-Host
$failed = @($results | Where-Object { $_.Status -like 'FAILED*' })
if ($failed.Count -gt 0) {
    Write-Host "##vso[task.logissue type=error]有 $($failed.Count) 筆失敗，請檢視上方輸出。"
    exit 1
}
Write-Host '全部完成。' -ForegroundColor Green
