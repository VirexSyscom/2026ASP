[CmdletBinding()]
param(
    [string]$SubscriptionId = $env:ARM_SUBSCRIPTION_ID,
    [string]$TenantId = $env:ARC_TENANT_ID,
    [string]$ResourceGroup = $env:ARC_RESOURCE_GROUP,
    [string]$Location = $env:ARC_LOCATION,
    [string]$MachineName = $env:ARC_MACHINE_NAME,
    [string]$ServicePrincipalId = $env:ARC_SP_CLIENT_ID,
    [string]$ServicePrincipalSecret = $env:ARC_SP_CLIENT_SECRET,
    [string]$SqlSetupPath = $env:SQL2022_SETUP_PATH,
    [string]$SqlInstanceName = "MSSQLSERVER",
    [string]$SqlDatabaseName = "CRMData",
    [string]$SqlProductKey = $env:SQL2022_PRODUCT_KEY,
    [switch]$AllowAzureVmEvaluation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Assert-Value([string]$Name, [string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "缺少必要值：$Name"
    }
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-IsAzureVirtualMachine {
    try {
        $null = Invoke-RestMethod `
            -Headers @{ Metadata = "true" } `
            -Method Get `
            -Uri "http://169.254.169.254/metadata/instance?api-version=2021-02-01" `
            -TimeoutSec 2
        return $true
    }
    catch {
        return $false
    }
}

function Get-AgentStatus([string]$AgentPath) {
    try {
        $raw = & $AgentPath show status -j 2>$null | Out-String
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        $obj = $raw | ConvertFrom-Json
        if ($obj -is [string]) { return $obj }
        if ($null -ne $obj.status) { return [string]$obj.status }
        return $null
    }
    catch {
        return $null
    }
}

if (-not (Test-IsAdministrator)) {
    throw "此腳本必須以 Windows 本機系統管理員權限執行。"
}

foreach ($required in @{
    SubscriptionId = $SubscriptionId
    TenantId = $TenantId
    ResourceGroup = $ResourceGroup
    Location = $Location
    MachineName = $MachineName
    ServicePrincipalId = $ServicePrincipalId
    ServicePrincipalSecret = $ServicePrincipalSecret
}.GetEnumerator()) {
    Assert-Value $required.Key $required.Value
}

if ((Test-IsAzureVirtualMachine) -and -not $AllowAzureVmEvaluation) {
    throw @"
偵測到此主機是 Azure VM。Azure Arc-enabled Servers 不支援把 Azure VM 當正式生產 Arc Server。
請改在內部部署或其他雲端的 Windows Server 執行；僅測試時才明確傳入 -AllowAzureVmEvaluation，
並先依 Microsoft 測試文件停用 Azure VM Guest Agent、移除 VM extensions 並封鎖 IMDS。
"@
}

# 1. 安裝真實 SQL Server 2022 Database Engine（已有預設 instance 時保持冪等）。
$sqlServiceName = if ($SqlInstanceName -eq "MSSQLSERVER") { "MSSQLSERVER" } else { "MSSQL`$$SqlInstanceName" }
$sqlService = Get-Service -Name $sqlServiceName -ErrorAction SilentlyContinue

if ($null -eq $sqlService) {
    Assert-Value "SQL2022_SETUP_PATH" $SqlSetupPath
    if (-not (Test-Path -LiteralPath $SqlSetupPath -PathType Leaf)) {
        throw "找不到 SQL Server 2022 setup.exe：$SqlSetupPath"
    }

    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $setupArguments = @(
        "/Q"
        "/ACTION=Install"
        "/FEATURES=SQLENGINE"
        "/INSTANCENAME=$SqlInstanceName"
        "/SQLSVCACCOUNT=`"NT Service\$sqlServiceName`""
        "/SQLSVCSTARTUPTYPE=Automatic"
        "/SQLSYSADMINACCOUNTS=`"$currentIdentity`" `"BUILTIN\Administrators`""
        "/TCPENABLED=1"
        "/UPDATEENABLED=1"
        "/SUPPRESSPRIVACYSTATEMENTNOTICE"
        "/IACCEPTSQLSERVERLICENSETERMS"
    )
    if (-not [string]::IsNullOrWhiteSpace($SqlProductKey)) {
        $setupArguments += "/PID=`"$SqlProductKey`""
    }

    Write-Host "安裝 SQL Server 2022 Database Engine..."
    $setup = Start-Process -FilePath $SqlSetupPath -ArgumentList $setupArguments -Wait -PassThru
    if ($setup.ExitCode -notin @(0, 3010)) {
        throw "SQL Server Setup 失敗，ExitCode=$($setup.ExitCode)。請檢查 SQL Setup Bootstrap\Log。"
    }
    if ($setup.ExitCode -eq 3010) {
        Write-Warning "SQL Server Setup 要求重新啟動；若服務尚未啟動，請重啟後重新執行 Pipeline。"
    }
}

$sqlService = Get-Service -Name $sqlServiceName -ErrorAction Stop
if ($sqlService.Status -ne "Running") {
    Start-Service -Name $sqlServiceName
}

# 2. 在真實 SQL Server 建立 CRMData；系統資料庫由 SQL Server 自己建立。
$serverName = if ($SqlInstanceName -eq "MSSQLSERVER") { "localhost" } else { "localhost\$SqlInstanceName" }
$connectionString = "Server=$serverName;Database=master;Integrated Security=True;Encrypt=True;TrustServerCertificate=True;Connection Timeout=30"
$connection = [System.Data.SqlClient.SqlConnection]::new($connectionString)
try {
    $connection.Open()
    $command = $connection.CreateCommand()
    $escapedName = $SqlDatabaseName.Replace("'", "''")
    $quotedName = $SqlDatabaseName.Replace("]", "]]" )
    $command.CommandText = "IF DB_ID(N'$escapedName') IS NULL CREATE DATABASE [$quotedName];"
    $null = $command.ExecuteNonQuery()
}
finally {
    $connection.Dispose()
}
Write-Host "SQL database '$SqlDatabaseName' 已確認存在。"

# 3. 安裝 Azure Connected Machine Agent。
$agentPath = Join-Path $env:ProgramW6432 "AzureConnectedMachineAgent\azcmagent.exe"
if (-not (Test-Path -LiteralPath $agentPath -PathType Leaf)) {
    $workDir = Join-Path $env:ProgramData "AzureArcSetup"
    $msiPath = Join-Path $workDir "AzureConnectedMachineAgent.msi"
    $msiLog = Join-Path $workDir "AzureConnectedMachineAgent-install.log"
    New-Item -ItemType Directory -Path $workDir -Force | Out-Null

    Write-Host "下載並安裝 Azure Connected Machine Agent..."
    Invoke-WebRequest -UseBasicParsing -Uri "https://aka.ms/AzureConnectedMachineAgent" -OutFile $msiPath
    $msi = Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /qn /norestart /l*v `"$msiLog`"" -Wait -PassThru
    if ($msi.ExitCode -notin @(0, 3010, 1641)) {
        throw "Azure Connected Machine Agent 安裝失敗，ExitCode=$($msi.ExitCode)，Log=$msiLog"
    }
}

if (-not (Test-Path -LiteralPath $agentPath -PathType Leaf)) {
    throw "Azure Connected Machine Agent 安裝後找不到 azcmagent.exe。"
}

# 4. 由真實 Agent 主動建立 Microsoft.HybridCompute/machines 資源。
$status = Get-AgentStatus $agentPath
if ($status -ne "Connected") {
    Write-Host "將真實 Windows Server 連接至 Azure Arc..."
    $connectArgs = @(
        "connect"
        "--service-principal-id", $ServicePrincipalId
        "--service-principal-secret", $ServicePrincipalSecret
        "--tenant-id", $TenantId
        "--subscription-id", $SubscriptionId
        "--resource-group", $ResourceGroup
        "--location", $Location
        "--resource-name", $MachineName
        "--cloud", "AzureCloud"
        "--tags", "Environment=demo,Workload=CRM,ManagedBy=Terraform"
    )
    & $agentPath @connectArgs
    if ($LASTEXITCODE -ne 0) {
        throw "azcmagent connect 失敗，ExitCode=$LASTEXITCODE。"
    }
}

$status = Get-AgentStatus $agentPath
if ($status -ne "Connected") {
    throw "Azure Connected Machine Agent 狀態不是 Connected；目前狀態：$status"
}

Write-Host "Azure Arc onboarding 完成：Machine=$MachineName, Status=$status"
Write-Host "後續由 Pipeline 安裝 WindowsAgent.SqlServer 並等待真實 SQL inventory。"
