$ErrorActionPreference = "Continue"

# ============================================================
# ORION SYSPULSE
# WINDOWS OBSERVABILITY AGENT
# ============================================================

$ConfigPath = Join-Path $PSScriptRoot "config.json"
$LogPath    = Join-Path $PSScriptRoot "agent.log"

# ============================================================
# LOGGING
# ============================================================

function Log {
    param(
        [string]$Message
    )

    try {
        Add-Content `
            -Path $LogPath `
            -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message"
    }
    catch {
    }
}

# ============================================================
# CONFIGURATION
# ============================================================

function Load-Config {

    if (-not (Test-Path $ConfigPath)) {
        throw "Configuration file not found: $ConfigPath"
    }

    $config = Get-Content `
        -Path $ConfigPath `
        -Raw |
        ConvertFrom-Json

    if ($null -eq $config.collector) {
        throw "collector configuration missing"
    }

    if ([string]::IsNullOrWhiteSpace(
        [string]$config.collector.endpoint
    )) {
        throw "collector.endpoint is missing"
    }

    if ([string]::IsNullOrWhiteSpace(
        [string]$config.collector.token
    )) {
        throw "collector.token is missing"
    }

    return $config
}

# ============================================================
# SIZE
# ============================================================

function Get-SizeGB {
    param(
        [double]$Bytes
    )

    if ($Bytes -le 0) {
        return 0
    }

    return [math]::Round(
        ($Bytes / 1GB),
        2
    )
}

# ============================================================
# SYSTEM
# ============================================================

function Get-SystemInfo {

    try {

        $computer =
            Get-CimInstance Win32_ComputerSystem

        return @{
            manufacturer = [string]$computer.Manufacturer
            model        = [string]$computer.Model
            domain       = [string]$computer.Domain
            totalMemoryGB =
                Get-SizeGB (
                    [double]$computer.TotalPhysicalMemory
                )
        }

    }
    catch {

        return @{
            manufacturer = "-"
            model        = "-"
            domain       = "-"
            totalMemoryGB = 0
        }
    }
}

# ============================================================
# OS
# ============================================================

function Get-OsInfo {

    try {

        $os =
            Get-CimInstance Win32_OperatingSystem

        return @{
            name =
                [string]$os.Caption

            version =
                [string]$os.Version

            build =
                [string]$os.BuildNumber

            architecture =
                [string]$os.OSArchitecture
        }

    }
    catch {

        return @{
            name = "-"
            version = "-"
            build = "-"
            architecture = "-"
        }
    }
}

# ============================================================
# CPU
# ============================================================

function Get-CpuInfo {

    try {

        $cpu =
            Get-CimInstance Win32_Processor |
            Select-Object -First 1

        $usage = 0

        try {

            $counter =
                Get-Counter `
                    "\Processor(_Total)\% Processor Time" `
                    -ErrorAction Stop

            $usage =
                [math]::Round(
                    [double]$counter.CounterSamples[0].CookedValue,
                    2
                )

        }
        catch {

            try {

                $sample =
                    Get-CimInstance `
                        Win32_Processor

                $usage =
                    [math]::Round(
                        (
                            $sample |
                            Measure-Object `
                                -Property LoadPercentage `
                                -Average
                        ).Average,
                        2
                    )
            }
            catch {
                $usage = 0
            }
        }

        return @{
            name =
                [string]$cpu.Name

            cores =
                [int]$cpu.NumberOfLogicalProcessors

            usagePercent =
                $usage
        }

    }
    catch {

        return @{
            name = "-"
            cores = 0
            usagePercent = 0
        }
    }
}

# ============================================================
# MEMORY
# ============================================================

function Get-MemoryInfo {

    try {

        $os =
            Get-CimInstance Win32_OperatingSystem

        $total =
            [double]$os.TotalVisibleMemorySize * 1KB

        $free =
            [double]$os.FreePhysicalMemory * 1KB

        $used =
            $total - $free

        $percent = 0

        if ($total -gt 0) {

            $percent =
                [math]::Round(
                    ($used / $total) * 100,
                    2
                )
        }

        return @{
            total =
                "$(Get-SizeGB $total) GB"

            used =
                "$(Get-SizeGB $used) GB"

            free =
                "$(Get-SizeGB $free) GB"

            usedPercent =
                $percent
        }

    }
    catch {

        return @{
            total = "0 GB"
            used = "0 GB"
            free = "0 GB"
            usedPercent = 0
        }
    }
}
# ============================================================
# DISK
# ============================================================

function Get-DiskInfo {

    $volumes = @()

    $totalMB = 0
    $freeMB  = 0

    try {

        foreach (
            $disk in Get-CimInstance Win32_LogicalDisk `
                -Filter "DriveType=3"
        ) {

            $totalBytes = [double]$disk.Size
            $freeBytes  = [double]$disk.FreeSpace
            $usedBytes  = $totalBytes - $freeBytes

            $percent = 0

            if ($totalBytes -gt 0) {

                $percent =
                    [math\]::Round(
                        ($usedBytes / $totalBytes) * 100,
                        1
                    )
            }

            $driveTotalMB =
                [math\]::Round(
                    $totalBytes / 1MB,
                    2
                )

            $driveFreeMB =
                [math\]::Round(
                    $freeBytes / 1MB,
                    2
                )

            $driveUsedMB =
                [math\]::Round(
                    $usedBytes / 1MB,
                    2
                )

            $totalMB += $driveTotalMB
            $freeMB  += $driveFreeMB

            $volumes += @{
                drive       = [string]$disk.DeviceID
                Name        = [string]$disk.DeviceID
                totalMB     = $driveTotalMB
                freeMB      = $driveFreeMB
                usedMB      = $driveUsedMB
                usedPercent = $percent
            }
        }

    }
    catch {

        Log (
            "Disk collector error: " +
            $_.Exception.Message
        )
    }

    $overallUsedPercent = 0

    if ($totalMB -gt 0) {

        $overallUsedPercent =
            [math\]::Round(
                (
                    ($totalMB - $freeMB)
                    /
                    $totalMB
                ) * 100,
                1
            )
    }

    return @{
        totalMB     = $totalMB
        freeMB      = $freeMB
        usedMB      = ($totalMB - $freeMB)
        usedPercent = $overallUsedPercent
        volumes     = $volumes
    }
}
# ============================================================
# NETWORK
# ============================================================

function Get-NetworkInfo {

    $ip = "-"

    try {

        $ip =
            Get-NetIPAddress `
                -AddressFamily IPv4 `
                -ErrorAction Stop |
            Where-Object {

                $_.IPAddress -notlike "127.*" -and
                $_.IPAddress -notlike "169.254.*"

            } |
            Sort-Object `
                -Property InterfaceIndex |
            Select-Object -First 1 `
                -ExpandProperty IPAddress

    }
    catch {
    }

    return @{
        ip = [string]$ip
    }
}

# ============================================================
# UPTIME
# ============================================================

function Get-Uptime {

    try {

        $os =
            Get-CimInstance Win32_OperatingSystem

        $boot =
            [datetime]$os.LastBootUpTime

        $span =
            New-TimeSpan `
                -Start $boot `
                -End (Get-Date)

        $days =
            [math]::Floor(
                $span.TotalDays
            )

        $hours =
            $span.Hours

        $minutes =
            $span.Minutes

        return @{
            boot =
                $boot.ToUniversalTime().ToString("o")

            seconds =
                [int]$span.TotalSeconds

            display =
                "${days}d ${hours}h ${minutes}m"
        }

    }
    catch {

        return @{
            boot = ""
            seconds = 0
            display = "-"
        }
    }
}

# ============================================================
# PATCHES
# ============================================================

function Get-Patches {

    $result = @()

    try {

        $hotfixes =
            Get-HotFix

        $valid = @()

        foreach (
            $hotfix in $hotfixes
        ) {

            $dateValue = $null

            try {

                if (
                    $null -ne $hotfix.InstalledOn -and
                    -not [string]::IsNullOrWhiteSpace(
                        [string]$hotfix.InstalledOn
                    )
                ) {

                    $dateValue =
                        [datetime]$hotfix.InstalledOn
                }

            }
            catch {

                $dateValue = $null
            }

            $valid += [PSCustomObject]@{

                HotFix =
                    $hotfix

                InstallDate =
                    $dateValue
            }
        }

        $valid =
            $valid |
            Sort-Object `
                -Property InstallDate `
                -Descending

        foreach (
            $item in
            $valid |
            Select-Object -First 30
        ) {

            $h =
                $item.HotFix

            $installed = ""

            if (
                $null -ne
                $item.InstallDate
            ) {

                $installed =
                    $item.InstallDate.ToString(
                        "yyyy-MM-dd"
                    )
            }

            $result += @{
                id =
                    [string]$h.HotFixID

                description =
                    [string]$h.Description

                installed =
                    $installed
            }
        }

    }
    catch {

        Log (
            "Patch collector warning: " +
            $_.Exception.Message
        )
    }

    return $result
}

# ============================================================
# PROCESSES
# ============================================================

function Get-Processes {
    $topCpu = @()
    $topMemory = @()
    $allProcesses = @()

    try {
        $procs = Get-Process -ErrorAction SilentlyContinue
        if (-not $procs) { 
            return @{ list = @(); topCpu = @(); topMemory = @() } 
        }

        # Build list using HashTables for reliable JSON conversion
        $processedList = foreach ($p in $procs) {
            $cpu = 0
            try { 
                if ($null -ne $p.CPU) { 
                    $cpu = [math]::Round([double]$p.CPU, 2) 
                } 
            } catch {}

            $wsMB = 0
            try { 
                if ($null -ne $p.WorkingSet64) { 
                    $wsMB = [math]::Round([double]$p.WorkingSet64 / 1MB, 2) 
                } 
            } catch {}

            $id = 0
            try { $id = [int]$p.Id } catch {}

            $name = ""
            try { $name = [string]$p.ProcessName } catch {}

            if ($id -gt 0) {
                @{
                    Name            = $name
                    ProcessName     = $name
                    PID             = $id
                    Id              = $id
                    ProcessId       = $id
                    PPID            = 0
                    ParentProcessId = 0
                    CPU             = $cpu
                    cpuTime         = $cpu
                    cpuTimeSeconds  = $cpu
                    Memory          = "$wsMB MB"
                    WorkingSetMB    = $wsMB
                }
            }
        }

        # Clean up collection array
        $validProcs = @($processedList | Where-Object { $_ -ne $null })

        # 1. Top 20 CPU Consuming Processes
        $topCpu = @($validProcs | Sort-Object { [double]$_.CPU } -Descending | Select-Object -First 20)

        # 2. Top 20 Memory Consuming Processes
        $topMemory = @($validProcs | Sort-Object { [double]$_.WorkingSetMB } -Descending | Select-Object -First 20)

        # 3. General List (up to 50)
        $allProcesses = @($validProcs | Select-Object -First 50)
    }
    catch {
        Log ("Process collector error: " + $_.Exception.Message)
    }

    return @{
        list      = $allProcesses
        topCpu    = $topCpu
        topMemory = $topMemory
    }
}
# ============================================================
# APPLICATIONS
# ============================================================

function Get-Applications {

    $result = @()

    try {

        $processes =
            Get-Process |
            Select-Object `
                ProcessName,
                Id

        foreach (
            $p in
            $processes |
            Select-Object -First 50
        ) {

            $result += @{
                name =
                    [string]$p.ProcessName

                pid =
                    [int]$p.Id
            }
        }

    }
    catch {
    }

    return $result
}

# ============================================================
# SERVICES
# ============================================================

function Get-Services {

    $result = @()

    try {

        foreach (
            $service in
            Get-Service |
            Select-Object -First 100
        ) {

            $result += @{
                name =
                    [string]$service.Name

                status =
                    [string]$service.Status
            }
        }

    }
    catch {
    }

    return $result
}

# ============================================================
# USERS
# ============================================================

function Get-Users {

    $result = @()

    try {

        $users =
            Get-CimInstance `
                Win32_ComputerSystem

        if ($users.UserName) {

            $result += @{
                username =
                    [string]$users.UserName
            }
        }

    }
    catch {
    }

    return $result
}


# ============================================================
# WINDOWS EVENT LOGS
# ============================================================

function Get-SystemLogs {
    try {

        Get-WinEvent -LogName System -MaxEvents 50 |
ForEach-Object {
    @{
        TimeCreated = $_.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
        Id = $_.Id
        LevelDisplayName = $_.LevelDisplayName
        ProviderName = $_.ProviderName
        Message = $_.Message
    }
	}}
    catch {
        @()
    }
}


# ============================================================
# COLLECT
# ============================================================

function Collect {

    $config =
        Load-Config

    $hostname =
        [string]$env:COMPUTERNAME

    $username =
        [string]$env:USERNAME

    $timestamp =
        (
            Get-Date
        ).ToUniversalTime().ToString("o")
	
	$diskInfo = Get-DiskInfo
	
    $report = @{
        schemaVersion = "1.0"

        agent = @{
            name =
                [string]$config.agent.name

            version =
                [string]$config.agent.version
        }

        serverId = $hostname

        serverName = $hostname

        hostname = $hostname

        username = $username

        timestamp = $timestamp

        system = Get-SystemInfo

        os = Get-OsInfo

        cpu = Get-CpuInfo

        memory = Get-MemoryInfo

		disk = @{
			totalMB     = $diskInfo.totalMB
			freeMB      = $diskInfo.freeMB
			usedMB      = $diskInfo.usedMB
			usedPercent = $diskInfo.usedPercent
		}
		
		volumes = $diskInfo.volumes
			
		logs = @(Get-SystemLogs)

        network = Get-NetworkInfo

        uptime = Get-Uptime

        patches = Get-Patches

        applications = Get-Applications

        processes = Get-Processes

        services = Get-Services

        users = Get-Users
    }

    return $report
}


# ============================================================
# SEND HEARTBEAT
# ============================================================

function Send-Heartbeat {

    try {

        $config =
            Load-Config

        $telemetryEndpoint =
            [string]$config.collector.endpoint

        # Convert:
        # http://server:5000/api/v1/telemetry
        #
        # into:
        # http://server:5000/api/v1/heartbeat

        $heartbeatEndpoint =
            $telemetryEndpoint -replace `
                "/api/v1/telemetry$", `
                "/api/v1/heartbeat"

        $token =
            [string]$config.collector.token

        $hostname =
            [string]$env:COMPUTERNAME

        $timestamp =
            (
                Get-Date
            ).ToUniversalTime().ToString("o")

        $heartbeat = @{
            serverId   = $hostname
            serverName = $hostname
            hostname   = $hostname
            timestamp  = $timestamp
        }

        $json =
            $heartbeat |
            ConvertTo-Json -Depth 10

        $headers = @{
            "X-Orion-SysPulse-Token" = $token
        }

        Invoke-RestMethod `
            -Uri $heartbeatEndpoint `
            -Method Post `
            -Headers $headers `
            -ContentType "application/json; charset=utf-8" `
            -Body $json `
            -TimeoutSec 5 `
            -ErrorAction Stop |
            Out-Null

        return $true
    }
    catch {

        Log (
            "Heartbeat failed: " +
            $_.Exception.Message
        )

        return $false
    }
}



# ============================================================
# SEND TELEMETRY
# ============================================================

function Send-Report {

    try {

        $config =
            Load-Config

        $endpoint =
            [string]$config.collector.endpoint

        $token =
            [string]$config.collector.token

        $report =
            Collect

        $json =
            $report |
            ConvertTo-Json -Depth 30

        $headers = @{
            "X-Orion-SysPulse-Token" =
                $token
        }

        Invoke-RestMethod `
            -Uri $endpoint `
            -Method Post `
            -Headers $headers `
            -ContentType "application/json; charset=utf-8" `
            -Body $json `
            -TimeoutSec 30 `
            -ErrorAction Stop |
            Out-Null

        #Log "Telemetry sent successfully"

        return $true
    }
    catch {

        Log (
            "Telemetry failed: " +
            $_.Exception.Message
        )

        return $false
    }
}

# ============================================================
# MAIN
# ============================================================

Log "Orion SysPulse Windows agent started"

# Manual one-shot mode
if ($args -contains "--once") {

    if (Send-Report) {

        Write-Host ""
        Write-Host `
            "Orion SysPulse: telemetry sent successfully." `
            -ForegroundColor Green

        exit 0
    }

    Write-Host ""
    Write-Host `
        "Orion SysPulse: telemetry failed." `
        -ForegroundColor Red

    exit 1
}

# ============================================================
# CONTINUOUS MODE
# ============================================================

$HeartbeatInterval = 5

try {

    $config =
        Load-Config

    $TelemetryInterval =
        [int]$config.agent.intervalSeconds

    if ($TelemetryInterval -lt 10) {
        $TelemetryInterval = 60
    }

}
catch {

    $TelemetryInterval = 60
}

$lastTelemetry =
    [datetime]::MinValue

# ============================================================
# IMMEDIATE HEARTBEAT
# ============================================================

Send-Heartbeat | Out-Null

# ============================================================
# CONTINUOUS LOOP
# ============================================================

while ($true) {

    # --------------------------------------------------------
    # HEARTBEAT
    # --------------------------------------------------------

    Send-Heartbeat | Out-Null

    # --------------------------------------------------------
    # TELEMETRY
    # --------------------------------------------------------

    $elapsed =
        ((Get-Date) - $lastTelemetry).TotalSeconds

    if (
        $lastTelemetry -eq [datetime]::MinValue -or
        $elapsed -ge $TelemetryInterval
    ) {

        Send-Report | Out-Null

        $lastTelemetry =
            Get-Date
    }

    # --------------------------------------------------------
    # WAIT
    # --------------------------------------------------------

    Start-Sleep `
        -Seconds $HeartbeatInterval
}