param(
    [Parameter(Mandatory = $true)]
    [string]$Command
)

$ServiceName = "OrionSysPulse"

function Test-Administrator {

    $currentUser =
        [Security.Principal.WindowsIdentity\]::GetCurrent()

    $principal =
        New-Object Security.Principal.WindowsPrincipal(
            $currentUser
        )

    if (-not $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole\]::Administrator
    )) {

        Write-Host ""
        Write-Host "Please run PowerShell as Administrator."
        Write-Host ""

        exit 1
    }
}

function Start-Orion {

    Write-Host ""
    Write-Host "Starting Orion SysPulse..."

    if (Get-Service $ServiceName -ErrorAction SilentlyContinue) {

        Set-Service `
            -Name $ServiceName `
            -StartupType Automatic

        Start-Service `
            -Name $ServiceName

        Write-Host "Service started."
    }
    else {

        Write-Host "Service is not installed."
    }
}

function Enable-Orion {

    Write-Host ""
    Write-Host "Enabling Orion SysPulse..."

    if (Get-Service $ServiceName -ErrorAction SilentlyContinue) {

        Set-Service `
            -Name $ServiceName `
            -StartupType Automatic

        Start-Service `
            -Name $ServiceName

        Write-Host "Service enabled."
    }
    else {

        Write-Host "Service is not installed."
    }
}

function Stop-Orion {

    Write-Host ""
    Write-Host "Stopping Orion SysPulse..."

    if (Get-Service $ServiceName -ErrorAction SilentlyContinue) {

        Stop-Service `
            -Name $ServiceName `
            -Force

        Write-Host "Service stopped."
    }
    else {

        Write-Host "Service is not installed."
    }
}

function Restart-Orion {

    Write-Host ""
    Write-Host "Restarting Orion SysPulse..."

    if (Get-Service $ServiceName -ErrorAction SilentlyContinue) {

        Restart-Service `
            -Name $ServiceName `
            -Force

        Write-Host "Service restarted."
    }
    else {

        Write-Host "Service is not installed."
    }
}

function Status-Orion {

    Write-Host ""

    $svc = Get-Service `
        -Name $ServiceName `
        -ErrorAction SilentlyContinue

    if ($svc) {

        $serviceInfo = Get-CimInstance Win32_Service `
            -Filter "Name='$ServiceName'"

        Write-Host "Orion SysPulse Status"
        Write-Host "----------------------"

        Write-Host "Name        :" $serviceInfo.Name
        Write-Host "DisplayName :" $serviceInfo.DisplayName
        Write-Host "Status      :" $svc.Status
        Write-Host "StartupType :" $serviceInfo.StartMode
        Write-Host "ProcessId   :" $serviceInfo.ProcessId

        Write-Host ""
    }
    else {

        Write-Host "Service is not installed."
    }
}

function Disable-Orion {

    Write-Host ""
    Write-Host "Disabling Orion SysPulse..."

    if (Get-Service $ServiceName -ErrorAction SilentlyContinue) {

        Stop-Service `
            -Name $ServiceName `
            -Force `
            -ErrorAction SilentlyContinue

        Set-Service `
            -Name $ServiceName `
            -StartupType Disabled

        Write-Host "Service disabled."
    }
    else {

        Write-Host "Service is not installed."
    }
}

function Remove-Orion {

    Write-Host ""
    Write-Host "Removing Orion SysPulse..."

    Stop-Service `
        -Name $ServiceName `
        -Force `
        -ErrorAction SilentlyContinue

    sc.exe delete $ServiceName | Out-Null

    Start-Sleep -Seconds 2

    Remove-Item `
        "C:\Program Files\Orion\SysPulse" `
        -Recurse `
        -Force `
        -ErrorAction SilentlyContinue

    Remove-Item `
        "C:\ProgramData\Orion\SysPulse" `
        -Recurse `
        -Force `
        -ErrorAction SilentlyContinue

    Remove-Item `
        "C:\Windows\Temp\orion*" `
        -Recurse `
        -Force `
        -ErrorAction SilentlyContinue

    Remove-Item `
        "C:\Windows\orion.cmd" `
        -Force `
        -ErrorAction SilentlyContinue

    Write-Host ""
    Write-Host "Orion SysPulse removed successfully."
    Write-Host ""
}

Test-Administrator

switch ($Command.ToLower()) {

    "start" {
        Start-Orion
    }

    "stop" {
        Stop-Orion
    }

    "restart" {
        Restart-Orion
    }

    "status" {
        Status-Orion
    }

    "disable" {
        Disable-Orion
    }

    "remove" {
        Remove-Orion
    }

	"enable" {
		Enable-Orion
	}

    default {

        Write-Host ""
        Write-Host "Orion SysPulse Service Manager"
        Write-Host ""

        Write-Host "Usage:"
        Write-Host "  orion start"
        Write-Host "  orion stop"
        Write-Host "  orion restart"
        Write-Host "  orion status"
        Write-Host "  orion disable"
		Write-Host "  orion enable"
		Write-Host "  orion remove"
        Write-Host ""

        exit 1
    }
}
``