<#
.SYNOPSIS
  建立 Entra ID 帳號並指派 Azure RBAC「參與者 / 擁有者」權限（可在 Azure DevOps AzurePowerShell@5 Task 中執行）。
  預設直接在腳本內為每個新建帳號產生隨機密碼，並把密碼印在 Pipeline Log 與輸出 CSV。

.NOTES
  執行身分 (Service Connection 的 SPN 或 Managed Identity) 需要具備：
    1) Microsoft Graph 應用程式權限：User.ReadWrite.All (需 Admin Consent)，或 Entra 角色「User Administrator」
    2) Azure RBAC：Tenant Root Group (或 ALZ / 各 MG 與訂閱) 上的 Owner 或 User Access Administrator
    3) Entra 租用戶已驗證網域 ai365.com.tw
  可重複執行：帳號已存在則略過建立（不變更既有密碼）；角色已指派則略過。
#>
[CmdletBinding()]
param(
    [bool]$RandomPassword          = $true,             # 預設在腳本內為每個「新建」帳號產生隨機密碼；設為 $false 則用固定密碼
    [bool]$ShowPasswordInLog       = $true,             # 預設把密碼明文印在 Pipeline Log（看完請刪除該次 Run 的 Log）
    [string]$Password              = 'SyscomASP2026',   # $RandomPassword = $false 時使用的固定密碼
    [int]$PasswordLength           = 16,
    [string]$PasswordOutputFile    = '',                # 預設：$(Build.ArtifactStagingDirectory)\EntraUsers-InitialPasswords.csv
    [string]$UsageLocation         = 'TW',

    # 訂閱：以名稱關鍵字比對（-like "*關鍵字*"），也可直接填完整訂閱名稱或訂閱 ID
    [string]$WorkloadSubscription     = 'Workload',
    [string]$ConnectivitySubscription = 'Connectivity',

    # 管理群組 ID（若 ID 找不到，會改用顯示名稱比對）
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

# ------------------------------------------------------------
# 1. 輔助函式
# ------------------------------------------------------------
# 以密碼學安全亂數產生密碼：含大寫、小寫、數字、特殊符號各至少 1 個（排除 I l O 0 1 等易混淆字元）
function New-RandomPassword {
    param([int]$Length = 16)
    if ($Length -lt 12) { $Length = 12 }
    $sets = @('ABCDEFGHJKLMNPQRSTUVWXYZ', 'abcdefghijkmnopqrstuvwxyz', '23456789', '!@#$%^*-_=+')
    $all  = -join $sets
    $rng  = [System.Security.Cryptography.RandomNumberGenerator]::Create()

    $getInt = {
        param([int]$max)
        $b = New-Object byte[] 4
        do {
            $rng.GetBytes($b)
            $v = [BitConverter]::ToUInt32($b, 0)
        } while ($v -ge ([uint32]::MaxValue - ([uint32]::MaxValue % [uint32]$max)))
        return [int]($v % [uint32]$max)
    }

    $chars = New-Object System.Collections.Generic.List[char]
    foreach ($set in $sets) { $chars.Add($set[(& $getInt $set.Length)]) }          # 每類至少 1 個
    while ($chars.Count -lt $Length) { $chars.Add($all[(& $getInt $all.Length)]) }  # 補滿長度
    for ($i = $chars.Count - 1; $i -gt 0; $i--) {                                   # Fisher-Yates 洗牌
        $j = & $getInt ($i + 1)
        $tmp = $chars[$i]; $chars[$i] = $chars[$j]; $chars[$j] = $tmp
    }
    return -join $chars
}

# Microsoft Graph (使用 Az 的 Token，不需額外安裝 Graph 模組)
function Get-GraphHeaders {
    $t = (Get-AzAccessToken -ResourceUrl 'https://graph.microsoft.com' -ErrorAction Stop).Token
    if ($t -is [System.Security.SecureString]) { $t = ConvertFrom-SecureString -SecureString $t -AsPlainText }
    return @{ Authorization = "Bearer $t"; 'Content-Type' = 'application/json' }
}

function Get-StatusCode($err) {
    try { return [int]$err.Exception.Response.StatusCode } catch { return 0 }
}

function Get-OrNew-EntraUser {
    param([string]$Upn)

    $headers = Get-GraphHeaders
    $enc = [uri]::EscapeDataString($Upn)

    # 已存在就直接使用（不變更既有密碼）
    try {
        $u = Invoke-RestMethod -Method Get -Headers $headers `
             -Uri ('https://graph.microsoft.com/v1.0/users/{0}?$select=id,userPrincipalName,displayName' -f $enc)
        Write-Host "  [略過建立] 帳號已存在: $Upn ($($u.id))，不變更既有密碼" -ForegroundColor Yellow
        $u | Add-Member -NotePropertyName InitialPassword -NotePropertyValue '' -Force
        return $u
    }
    catch {
        if ((Get-StatusCode $_) -ne 404) { throw "查詢使用者 $Upn 失敗: $($_.ErrorDetails.Message)" }
    }

    # 決定密碼：隨機 or 固定
    $pwd = if ($RandomPassword) { New-RandomPassword -Length $PasswordLength } else { $Password }

    $prefix = $Upn.Split('@')[0]
    $body = @{
        accountEnabled    = $true
        displayName       = $prefix
        mailNickname      = ($prefix -replace '[^a-zA-Z0-9_\-\.]', '')
        userPrincipalName = $Upn
        usageLocation     = $UsageLocation
        passwordProfile   = @{
            # 隨機密碼：要求首次登入變更；固定密碼：維持不強制變更
            forceChangePasswordNextSignIn = [bool]$RandomPassword
            password                      = $pwd
        }
    } | ConvertTo-Json -Depth 5

    try {
        $u = Invoke-RestMethod -Method Post -Headers $headers -Body $body `
             -Uri 'https://graph.microsoft.com/v1.0/users'
        Write-Host "  [已建立] $Upn ($($u.id))" -ForegroundColor Green
        $u | Add-Member -NotePropertyName InitialPassword -NotePropertyValue $pwd -Force
        return $u
    }
    catch {
        throw "建立使用者 $Upn 失敗: $($_.ErrorDetails.Message)"
    }
}

# ------------------------------------------------------------
# 2. Azure 範圍解析
# ------------------------------------------------------------
$allSubs = @(Get-AzSubscription -TenantId $ctx.Tenant.Id -ErrorAction Stop)
if ($allSubs.Count -eq 0) { throw '此身分看不到任何訂閱，請確認 RBAC。' }

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
    if (-not $mg) { throw "找不到管理群組: $Name" }
    return $mg.Id   # /providers/Microsoft.Management/managementGroups/<id>
}

function Resolve-RgScope {
    param([string]$RgName, [string]$PreferredSubId)

    # 先找偏好的訂閱，找不到再掃描所有訂閱
    $ordered = @()
    if ($PreferredSubId) { $ordered += $allSubs | Where-Object { $_.Id -eq $PreferredSubId } }
    $ordered += $allSubs | Where-Object { $_.Id -ne $PreferredSubId }

    foreach ($s in $ordered) {
        $c  = Set-AzContext -SubscriptionId $s.Id -TenantId $ctx.Tenant.Id
        $rg = Get-AzResourceGroup -Name $RgName -DefaultProfile $c -ErrorAction SilentlyContinue
        if ($rg) { return $rg.ResourceId }
    }
    throw "在所有可見訂閱中找不到資源群組: $RgName"
}

$workloadSub     = Resolve-Subscription $WorkloadSubscription
$connectivitySub = Resolve-Subscription $ConnectivitySubscription
Write-Host "Workload     訂閱: $($workloadSub.Name) ($($workloadSub.Id))"
Write-Host "Connectivity 訂閱: $($connectivitySub.Name) ($($connectivitySub.Id))"
Write-Host ("密碼模式: " + $(if ($RandomPassword) { "隨機 ($PasswordLength 碼，首次登入須變更)" } else { '固定密碼' }))

# ------------------------------------------------------------
# 3. 帳號與權限清單
#    Type: Sub / MG / RG    Role: Contributor / Owner
#    (UPN 依需求原樣保留，包含拼字)
# ------------------------------------------------------------
$assignments = @(
    @{ Upn='Workload_Sub_Contributor@ai365.com.tw';     Role='Contributor'; Type='Sub'; Target=$workloadSub.Id }
    @{ Upn='Connectivity_Sub_Contributor@ai365.com.tw'; Role='Contributor'; Type='Sub'; Target=$connectivitySub.Id }

    @{ Upn='ALZMG_Contributor@ai365.com.tw';   Role='Contributor'; Type='MG'; Target=$AlzMgName }
    @{ Upn='APMG_Contributor@ai365.com.tw';    Role='Contributor'; Type='MG'; Target=$ApMgName }
    @{ Upn='InfraMG_Contributor@ai365.com.tw'; Role='Contributor'; Type='MG'; Target=$InfraMgName }

    @{ Upn='Spoke_HR_RG_Owner@ai365.com.tw';       Role='Owner'; Type='RG'; Target='Spoke-HR-RG';      Hint=$workloadSub.Id }
    @{ Upn='UAT_Spoke_HR_RG_Owner@ai365.com.tw';   Role='Owner'; Type='RG'; Target='UAT-Spoke-HR-RG';  Hint=$workloadSub.Id }
    @{ Upn='AzureMigrateRG_Owner@ai365.com.tw';   Role='Owner'; Type='RG'; Target='AzureMigrateRG';   Hint=$workloadSub.Id }
    @{ Upn='Spoke_Network_RG_Owner@ai365.com.tw'; Role='Owner'; Type='RG'; Target='Spoke-Network-RG'; Hint=$workloadSub.Id }
    @{ Upn='Hub_Network_RG_Owner@ai365.com.tw';   Role='Owner'; Type='RG'; Target='Hub-Network-RG';   Hint=$connectivitySub.Id }
)

# ------------------------------------------------------------
# 4. 執行
# ------------------------------------------------------------
$results = New-Object System.Collections.Generic.List[object]

foreach ($a in $assignments) {
    Write-Host "`n=== $($a.Upn) -> $($a.Role) @ $($a.Type): $($a.Target)" -ForegroundColor Cyan
    $status = 'OK'; $scope = ''; $initPwd = ''
    try {
        # 解析範圍
        switch ($a.Type) {
            'Sub' { $scope = "/subscriptions/$($a.Target)" }
            'MG'  { $scope = Resolve-MgScope $a.Target }
            'RG'  { $scope = Resolve-RgScope -RgName $a.Target -PreferredSubId $a.Hint }
        }
        Write-Host "  Scope: $scope"

        # 建立 / 取得帳號
        $user    = Get-OrNew-EntraUser -Upn $a.Upn
        $initPwd = $user.InitialPassword

        # 已有相同指派則略過
        $exist = Get-AzRoleAssignment -ObjectId $user.id -Scope $scope -RoleDefinitionName $a.Role -ErrorAction SilentlyContinue |
                 Where-Object { $_.Scope -eq $scope }
        if ($exist) {
            Write-Host "  [略過指派] 已具備 $($a.Role)" -ForegroundColor Yellow
            $status = 'Already assigned'
        }
        else {
            # 新帳號 Entra 複寫需要時間，遇 PrincipalNotFound 自動重試
            $done = $false
            for ($i = 1; $i -le 8 -and -not $done; $i++) {
                try {
                    New-AzRoleAssignment -ObjectId $user.id -ObjectType User `
                        -RoleDefinitionName $a.Role -Scope $scope -ErrorAction Stop | Out-Null
                    $done = $true
                    Write-Host "  [已指派] $($a.Role)" -ForegroundColor Green
                }
                catch {
                    if ($_.Exception.Message -match 'PrincipalNotFound|does not exist in the directory|replication') {
                        Write-Host "  等待 Entra 複寫… ($i/8)" -ForegroundColor DarkYellow
                        Start-Sleep -Seconds 15
                    }
                    elseif ($_.Exception.Message -match 'already exists') { $done = $true; $status = 'Already assigned' }
                    else { throw }
                }
            }
            if (-not $done) { throw '角色指派重試後仍失敗 (Entra 複寫逾時)。' }
        }
    }
    catch {
        $status = "FAILED: $($_.Exception.Message)"
        Write-Host "  [失敗] $($_.Exception.Message)" -ForegroundColor Red
    }
    $results.Add([pscustomobject]@{ UPN=$a.Upn; Role=$a.Role; Scope=$scope; Status=$status; InitialPassword=$initPwd })
}

# ------------------------------------------------------------
# 5. 結果彙總
# ------------------------------------------------------------
Write-Host "`n================ 執行結果 ================" -ForegroundColor Cyan
$results | Select-Object UPN, Role, Scope, Status | Format-Table -AutoSize -Wrap | Out-String -Width 250 | Write-Host

if ($RandomPassword) {
    # (a) 輸出 CSV
    if (-not $PasswordOutputFile) {
        $dir = if ($env:BUILD_ARTIFACTSTAGINGDIRECTORY) { $env:BUILD_ARTIFACTSTAGINGDIRECTORY } else { (Get-Location).Path }
        $PasswordOutputFile = Join-Path $dir 'EntraUsers-InitialPasswords.csv'
    }
    $results | Where-Object { $_.InitialPassword } |
        Select-Object UPN, InitialPassword |
        Export-Csv -Path $PasswordOutputFile -NoTypeInformation -Encoding UTF8
    Write-Host "隨機密碼已輸出至: $PasswordOutputFile" -ForegroundColor Yellow

    # (b) 直接印在 Log（明文）
    if ($ShowPasswordInLog) {
        Write-Host "`n======== 新建帳號的初始密碼 (明文，請立即記錄) ========" -ForegroundColor Magenta
        $results | Where-Object { $_.InitialPassword } |
            Select-Object UPN, InitialPassword | Format-Table -AutoSize | Out-String -Width 250 | Write-Host
    }
}

$failed = @($results | Where-Object { $_.Status -like 'FAILED*' })
if ($failed.Count -gt 0) {
    Write-Host "##vso[task.logissue type=error]有 $($failed.Count) 筆失敗，請檢視上方輸出。"
    exit 1
}
Write-Host '全部完成。' -ForegroundColor Green
