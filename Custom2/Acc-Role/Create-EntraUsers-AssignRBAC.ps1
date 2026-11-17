<#
.SYNOPSIS
  建立 11 個 Entra ID 帳號並指派 Azure RBAC「參與者 / 擁有者」權限。
  可在 Azure DevOps AzurePowerShell@5 Task 中執行。
.NOTES
  執行身分需要：
    1) Microsoft Graph 應用程式權限 User.ReadWrite.All（需 Admin Consent），或 Entra 角色 User Administrator
    2) Azure RBAC：目標範圍上的 Owner 或 User Access Administrator
    3) Entra 租用戶已驗證網域 ai365.com.tw
  可重複執行：帳號已存在則略過建立；相同角色已指派則略過。
#>
[CmdletBinding()]
param(
    [bool]$RandomPassword          = $true,
    [bool]$ShowPasswordInLog       = $true,
    [string]$Password              = 'SyscomASP2026',
    [int]$PasswordLength           = 16,
    [string]$PasswordOutputFile    = '',
    [string]$UsageLocation         = 'TW',
    [string]$WorkloadSubscription     = 'Workload',
    [string]$ConnectivitySubscription = 'Connectivity',
    [string]$AlzMgName   = 'ALZ',
    [string]$ApMgName    = 'AP Group',
    [string]$InfraMgName = 'Infra Group'
)

$ErrorActionPreference = 'Stop'

foreach ($m in 'Az.Accounts', 'Az.Resources') {
    if (-not (Get-Module -ListAvailable -Name $m)) {
        throw "找不到模組 $m，請先安裝 Az 模組。"
    }
}
Import-Module Az.Accounts, Az.Resources -ErrorAction Stop

$originalContext = Get-AzContext
if (-not $originalContext) {
    throw '目前沒有 Azure 登入內容。請在 Azure DevOps 使用 AzurePowerShell@5 Task（含 azureSubscription）執行，或先 Connect-AzAccount -UseDeviceAuthentication。'
}
$ctx = $originalContext
Write-Host "目前身分: $($ctx.Account.Id) | Tenant: $($ctx.Tenant.Id)" -ForegroundColor Cyan

function New-RandomPassword {
    param([int]$Length = 16)
    if ($Length -lt 12) { $Length = 12 }
    $sets = @('ABCDEFGHJKLMNPQRSTUVWXYZ', 'abcdefghijkmnopqrstuvwxyz', '23456789', '!@#$%^*-_=+')
    $all = -join $sets
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $getInt = {
            param([int]$Max)
            $b = New-Object byte[] 4
            do {
                $rng.GetBytes($b)
                $v = [BitConverter]::ToUInt32($b, 0)
            } while ($v -ge ([uint32]::MaxValue - ([uint32]::MaxValue % [uint32]$Max)))
            [int]($v % [uint32]$Max)
        }
        $chars = New-Object System.Collections.Generic.List[char]
        foreach ($set in $sets) { $chars.Add($set[(& $getInt $set.Length)]) }
        while ($chars.Count -lt $Length) { $chars.Add($all[(& $getInt $all.Length)]) }
        for ($i = $chars.Count - 1; $i -gt 0; $i--) {
            $j = & $getInt ($i + 1)
            $tmp = $chars[$i]; $chars[$i] = $chars[$j]; $chars[$j] = $tmp
        }
        -join $chars
    }
    finally {
        $rng.Dispose()
    }
}

function Get-GraphHeaders {
    $t = (Get-AzAccessToken -ResourceUrl 'https://graph.microsoft.com' -ErrorAction Stop).Token
    if ($t -is [System.Security.SecureString]) {
        $t = ConvertFrom-SecureString -SecureString $t -AsPlainText
    }
    @{ Authorization = "Bearer $t"; 'Content-Type' = 'application/json' }
}

function Get-StatusCode($ErrorRecord) {
    try { [int]$ErrorRecord.Exception.Response.StatusCode } catch { 0 }
}

function Get-OrNew-EntraUser {
    param([string]$Upn)
    $headers = Get-GraphHeaders
    $enc = [uri]::EscapeDataString($Upn)
    try {
        $u = Invoke-RestMethod -Method Get -Headers $headers -Uri ('https://graph.microsoft.com/v1.0/users/{0}?$select=id,userPrincipalName,displayName' -f $enc)
        Write-Host "  [略過建立] 帳號已存在: $Upn ($($u.id))，不變更既有密碼" -ForegroundColor Yellow
        $u | Add-Member -NotePropertyName InitialPassword -NotePropertyValue '' -Force
        return $u
    }
    catch {
        if ((Get-StatusCode $_) -ne 404) { throw "查詢使用者 $Upn 失敗: $($_.ErrorDetails.Message)" }
    }

    $pwd = if ($RandomPassword) { New-RandomPassword -Length $PasswordLength } else { $Password }
    $prefix = $Upn.Split('@')[0]
    $body = @{
        accountEnabled    = $true
        displayName       = $prefix
        mailNickname      = ($prefix -replace '[^a-zA-Z0-9_\-.]', '')
        userPrincipalName = $Upn
        usageLocation     = $UsageLocation
        passwordProfile   = @{
            forceChangePasswordNextSignIn = [bool]$RandomPassword
            password = $pwd
        }
    } | ConvertTo-Json -Depth 5

    try {
        $u = Invoke-RestMethod -Method Post -Headers $headers -Body $body -Uri 'https://graph.microsoft.com/v1.0/users'
        Write-Host "  [已建立] $Upn ($($u.id))" -ForegroundColor Green
        $u | Add-Member -NotePropertyName InitialPassword -NotePropertyValue $pwd -Force
        return $u
    }
    catch {
        throw "建立使用者 $Upn 失敗: $($_.ErrorDetails.Message)"
    }
}

$allSubs = @(Get-AzSubscription -TenantId $ctx.Tenant.Id -ErrorAction Stop)
if ($allSubs.Count -eq 0) { throw '此身分看不到任何訂閱，請確認 RBAC。' }

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
    if (-not $mg) { throw "找不到管理群組: $Name" }
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
    throw "在所有可見訂閱中找不到資源群組: $RgName"
}

$workloadSub = Resolve-Subscription $WorkloadSubscription
$connectivitySub = Resolve-Subscription $ConnectivitySubscription

$assignments = @(
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
    foreach ($a in $assignments) {
        Write-Host "`n=== $($a.Upn) -> $($a.Role) @ $($a.Type): $($a.Target)" -ForegroundColor Cyan
        $status = 'OK'; $scope = ''; $initPwd = ''
        try {
            # 先建立或取得帳號，再解析 RBAC Scope。
            $user = Get-OrNew-EntraUser -Upn $a.Upn
            $initPwd = $user.InitialPassword

            switch ($a.Type) {
                'Sub' { $scope = "/subscriptions/$($a.Target)" }
                'MG'  { $scope = Resolve-MgScope $a.Target }
                'RG'  { $scope = Resolve-RgScope -RgName $a.Target -PreferredSubId $a.Hint }
                default { throw "不支援的範圍類型: $($a.Type)" }
            }
            Write-Host "  Scope: $scope"

            $exist = Get-AzRoleAssignment -ObjectId $user.id -Scope $scope -RoleDefinitionName $a.Role -ErrorAction SilentlyContinue |
                Where-Object { $_.Scope -eq $scope -and $_.RoleDefinitionName -eq $a.Role }
            if ($exist) {
                Write-Host "  [略過指派] 已具備 $($a.Role)" -ForegroundColor Yellow
                $status = 'Already assigned'
            }
            else {
                $done = $false
                for ($i = 1; $i -le 8 -and -not $done; $i++) {
                    try {
                        New-AzRoleAssignment -ObjectId $user.id -ObjectType User -RoleDefinitionName $a.Role -Scope $scope -ErrorAction Stop | Out-Null
                        $done = $true
                        Write-Host "  [已指派] $($a.Role)" -ForegroundColor Green
                    }
                    catch {
                        if ($_.Exception.Message -match 'PrincipalNotFound|does not exist in the directory|replication') {
                            Write-Host "  等待 Entra 複寫... ($i/8)" -ForegroundColor DarkYellow
                            Start-Sleep -Seconds 15
                        }
                        elseif ($_.Exception.Message -match 'already exists') {
                            $done = $true; $status = 'Already assigned'
                        }
                        else { throw }
                    }
                }
                if (-not $done) { throw '角色指派重試後仍失敗（Entra 複寫逾時）。' }
            }
        }
        catch {
            $status = "FAILED: $($_.Exception.Message)"
            Write-Host "  [失敗] $($_.Exception.Message)" -ForegroundColor Red
        }
        $results.Add([pscustomobject]@{ UPN=$a.Upn; Role=$a.Role; Scope=$scope; Status=$status; InitialPassword=$initPwd })
    }
}
finally {
    if ($originalContext) {
        Set-AzContext -Context $originalContext -Scope Process -ErrorAction SilentlyContinue | Out-Null
    }
}

Write-Host "`n================ 執行結果 ================" -ForegroundColor Cyan
$results | Select-Object UPN, Role, Scope, Status | Format-Table -AutoSize -Wrap | Out-String -Width 250 | Write-Host

if ($RandomPassword) {
    if (-not $PasswordOutputFile) {
        $dir = if ($env:BUILD_ARTIFACTSTAGINGDIRECTORY) { $env:BUILD_ARTIFACTSTAGINGDIRECTORY } else { (Get-Location).Path }
        $PasswordOutputFile = Join-Path $dir 'EntraUsers-InitialPasswords.csv'
    }
    $results | Where-Object { $_.InitialPassword } | Select-Object UPN, InitialPassword |
        Export-Csv -Path $PasswordOutputFile -NoTypeInformation -Encoding UTF8
    Write-Host "隨機密碼已輸出至: $PasswordOutputFile" -ForegroundColor Yellow
    if ($ShowPasswordInLog) {
        Write-Host "`n======== 新建帳號的初始密碼（明文，請立即記錄）========" -ForegroundColor Magenta
        $results | Where-Object { $_.InitialPassword } | Select-Object UPN, InitialPassword |
            Format-Table -AutoSize | Out-String -Width 250 | Write-Host
    }
}

$failed = @($results | Where-Object { $_.Status -like 'FAILED*' })
if ($failed.Count -gt 0) {
    Write-Host "##vso[task.logissue type=error]有 $($failed.Count) 筆失敗，請檢視上方輸出。"
    exit 1
}
Write-Host '全部完成。' -ForegroundColor Green
