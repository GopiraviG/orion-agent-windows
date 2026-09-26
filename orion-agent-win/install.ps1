param(
    [Parameter(Mandatory = $true)]
    [string]$Server,

    [Parameter(Mandatory = $true)]
    [string]$Token,

    [string]$SystemName = $env:COMPUTERNAME,

    [int]$IntervalSeconds = 60
)

$ErrorActionPreference = "Stop"

$Server = $Server.TrimEnd("/")

$InstallPath = "C:\ProgramData\Orion\SysPulse"

$ConfigPath =
    Join-Path $InstallPath "config.json"

$AgentPath =
    Join-Path $InstallPath "agent.ps1"

$OrionPath =
    Join-Path $InstallPath "orion.ps1"

$NssmPath =
    Join-Path $InstallPath "nssm.exe"

$VersionPath =
    Join-Path $InstallPath "version.txt"

$LogPath =
    Join-Path $InstallPath "agent.log"

$ServiceName =
    "OrionSysPulse"

# ============================================================
# ADMIN CHECK
# ============================================================

$currentIdentity =
    [Security.Principal.WindowsIdentity]::GetCurrent()

$principal =
    New-Object Security.Principal.WindowsPrincipal(
        $currentIdentity
    )

if (-not $principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {

    throw "Please run PowerShell as Administrator."
}

# ============================================================
# INSTALL DIRECTORY
# ============================================================

New-Item `
    -ItemType Directory `
    -Path $InstallPath `
    -Force | Out-Null

# ============================================================
# CONFIGURATION
# ============================================================

Write-Host "[1/6] Downloading configuration..."

$ConfigDownloaded = $false

try {

    $ConfigUrl =
        "$Server/api/v1/config/$SystemName"

    Invoke-WebRequest `
        -Uri $ConfigUrl `
        -OutFile $ConfigPath `
        -UseBasicParsing

    $ConfigDownloaded = $true

    Write-Host `
        "Configuration downloaded successfully." `
        -ForegroundColor Green
}
catch {

    Write-Warning `
        "Remote config unavailable. Creating local configuration..."
}

if (-not $ConfigDownloaded) {

    $Config = @{

        agent = @{
            name = $SystemName
            version = "1.0.0"
            intervalSeconds = $IntervalSeconds
        }

        collector = @{
            endpoint = "$Server/api/v1/telemetry"
            token = $Token
        }

        collectors = @{
            system       = $true
            cpu          = $true
            memory       = $true
            disk         = $true
            network      = $true
            processes    = $true
            services     = $true
            applications = $true
            updates      = $true
            users        = $true
            uptime       = $true
            logs         = $true
        }
    }

    $Config |
        ConvertTo-Json -Depth 20 |
        Set-Content `
            -Path $ConfigPath `
            -Encoding UTF8
}

# ============================================================
# COPY FILES
# ============================================================

Write-Host "[2/6] Installing files..."

Copy-Item `
    "$PSScriptRoot\agent-windows.ps1" `
    $AgentPath `
    -Force

Copy-Item `
    "$PSScriptRoot\orion.ps1" `
    $OrionPath `
    -Force

Copy-Item `
    "$PSScriptRoot\nssm.exe" `
    $NssmPath `
    -Force

if (Test-Path "$PSScriptRoot\version.txt") {

    Copy-Item `
        "$PSScriptRoot\version.txt" `
        $VersionPath `
        -Force
}

# ============================================================
# TELEMETRY TEST
# ============================================================

Write-Host "[3/6] Testing telemetry..."

try {

    & powershell.exe `
        -NoProfile `
        -NonInteractive `
        -ExecutionPolicy Bypass `
        -File $AgentPath `
        --once

    Write-Host `
        "Telemetry test successful." `
        -ForegroundColor Green
}
catch {

    Write-Warning `
        "Telemetry test failed: $($_.Exception.Message)"
}

# ============================================================
# REMOVE OLD SERVICE
# ============================================================

Write-Host "[4/6] Removing existing service..."

if (Get-Service `
    $ServiceName `
    -ErrorAction SilentlyContinue) {

    try {

        Stop-Service `
            $ServiceName `
            -Force `
            -ErrorAction SilentlyContinue
    }
    catch {
    }

    try {

        & $NssmPath remove `
            $ServiceName `
            confirm | Out-Null
    }
    catch {
    }

    Start-Sleep -Seconds 2
}

# ============================================================
# INSTALL WINDOWS SERVICE
# ============================================================

Write-Host "[5/6] Installing Windows service..."

if (-not (Test-Path $NssmPath)) {

    throw "nssm.exe not found."
}

& $NssmPath install `
    $ServiceName `
    "powershell.exe"

& $NssmPath set `
    $ServiceName `
    DisplayName `
    "Orion SysPulse Agent"

& $NssmPath set `
    $ServiceName `
    Description `
    "Orion SysPulse Windows Telemetry Agent"
	
& $NssmPath set `
    $ServiceName `
    Application `
    "powershell.exe"

& $NssmPath set `
    $ServiceName `
    AppParameters `
    "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$AgentPath`""

& $NssmPath set `
    $ServiceName `
    AppDirectory `
    $InstallPath

& $NssmPath set `
    $ServiceName `
    Start `
    SERVICE_AUTO_START

& $NssmPath set `
    $ServiceName `
    AppStdout `
    "$InstallPath\service.out.log"

& $NssmPath set `
    $ServiceName `
    AppStderr `
    "$InstallPath\service.err.log"
	
sc.exe failure `
    $ServiceName `
    reset= 86400 `
    actions= restart/5000/restart/5000/restart/5000 |
    Out-Null

# ============================================================
# GLOBAL ORION COMMAND
# ============================================================

@'
@echo off
powershell.exe -ExecutionPolicy Bypass -File "C:\ProgramData\Orion\SysPulse\orion.ps1" %*
'@ |
Set-Content `
"C:\Windows\orion.cmd"

if (-not (Test-Path "C:\Windows\orion.cmd")) {

    throw "Failed to create Orion management command."
}

# ============================================================
# START SERVICE
# ============================================================

Write-Host "[6/6] Starting service..."

Start-Service `
    $ServiceName

Start-Sleep -Seconds 5

$ServiceInfo =
    Get-Service `
    $ServiceName

if ($ServiceInfo.Status -ne "Running") {

    throw "Service installed but is not running."
}

# ============================================================
# VERIFY
# ============================================================

$ServiceInfo =
    Get-Service `
    $ServiceName

Write-Host ""
Write-Host "==================================================" -ForegroundColor Green
Write-Host "       Orion SysPulse Agent Installed" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Green
Write-Host ""

Write-Host "Install Path:"
Write-Host "  $InstallPath"

Write-Host ""
Write-Host "Agent:"
Write-Host "  $AgentPath"

Write-Host ""
Write-Host "Configuration:"
Write-Host "  $ConfigPath"

Write-Host ""
Write-Host "Service:"
Write-Host "  $ServiceName"

Write-Host ""
Write-Host "Collector:"
Write-Host "  $Server/api/v1/telemetry"

Write-Host ""
Write-Host "Service Status:"
Write-Host "  $($ServiceInfo.Status)" -ForegroundColor Green

Write-Host ""
Write-Host "Management Commands:"
Write-Host "  orion status"
Write-Host "  orion stop"
Write-Host "  orion start"
Write-Host "  orion restart"
Write-Host "  orion disable"
Write-Host "  orion remove"
Write-Host "  orion enable"

Write-Host ""
Write-Host "Orion SysPulse is running." -ForegroundColor Green
Write-Host ""