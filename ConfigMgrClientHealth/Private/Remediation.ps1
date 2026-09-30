# Private\Remediation.ps1
# Remediation actions: client install/reinstall, WMI repair, admin share,
# reboot application, software metering, compliance refresh, and cache cleanup.
#
# These are the modernized equivalents of the original tool's remediation
# functions. They return structured result objects and log via
# Write-ClientHealthLog.

#region Client install / reinstall

function Resolve-ClientHealthClient {
    <#
    .SYNOPSIS
        Ensures the ConfigMgr client is installed and at the expected version.
    .DESCRIPTION
        If the client is missing, installs it from the configured share. If the
        client is present but below the minimum version and auto-upgrade is
        enabled, reinstalls it. Returns a structured result.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][string]$Share,
        [Parameter(Mandatory = $true)][string]$SiteCode,
        [Parameter(Mandatory = $true)][string]$Domain,
        [Parameter(Mandatory = $true)][string]$MinimumVersion,
        [Parameter(Mandatory = $false)][bool]$AutoUpgrade = $false,
        [Parameter(Mandatory = $false)][string[]]$InstallProperties = @()
    )

    $installed = Get-ClientHealthClientVersion
    $svc = Get-Service -Name ccmexec -ErrorAction SilentlyContinue

    if ($null -eq $svc -and [string]::IsNullOrWhiteSpace($installed)) {
        return Install-ClientHealthClient -Share $Share -SiteCode $SiteCode -Domain $Domain -InstallProperties $InstallProperties
    }

    if ($AutoUpgrade -and -not [string]::IsNullOrWhiteSpace($installed) -and $installed -lt $MinimumVersion) {
        return Install-ClientHealthClient -Share $Share -SiteCode $SiteCode -Domain $Domain -InstallProperties $InstallProperties -Reinstall
    }

    return [pscustomobject]@{ Name = 'ClientInstall'; Status = 'OK'; Detail = "Client present (version $installed)"; Remediated = $false }
}

function Install-ClientHealthClient {
    <#
    .SYNOPSIS
        Installs or reinstalls the ConfigMgr client from the configured share.
    .DESCRIPTION
        Locates ccmsetup.exe in the share, copies it locally, and runs it with
        the configured site code, domain, and install properties.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][string]$Share,
        [Parameter(Mandatory = $true)][string]$SiteCode,
        [Parameter(Mandatory = $true)][string]$Domain,
        [Parameter(Mandatory = $false)][string[]]$InstallProperties = @(),
        [Parameter(Mandatory = $false)][switch]$Reinstall
    )

    $source = Join-Path $Share 'ccmsetup.exe'
    if (-not (Test-Path -LiteralPath $source)) {
        return [pscustomobject]@{ Name = 'ClientInstall'; Status = 'Error'; Detail = "ccmsetup.exe not found at $source"; Remediated = $false }
    }

    $tempDir = Join-Path $env:TEMP 'ClientHealth'
    $null = New-Item -Path $tempDir -ItemType Directory -Force
    $localSetup = Join-Path $tempDir 'ccmsetup.exe'
    Copy-Item -LiteralPath $source -Destination $localSetup -Force

    $args = @('/source:"{0}"' -f $tempDir)
    $args += '/MP:'
    $args += 'SMSSITECODE={0}' -f $SiteCode
    if (-not [string]::IsNullOrWhiteSpace($Domain)) {
        $args += 'FSP={0}' -f $Domain
    }
    $args += $InstallProperties

    try {
        $proc = Start-Process -FilePath $localSetup -ArgumentList $args -Wait -PassThru
        $action = if ($Reinstall) { 'reinstalled' } else { 'installed' }
        if ($proc.ExitCode -eq 0) {
            return [pscustomobject]@{ Name = 'ClientInstall'; Status = 'Remediated'; Detail = "Client $action (exit $($proc.ExitCode))"; Remediated = $true }
        }
        return [pscustomobject]@{ Name = 'ClientInstall'; Status = 'Error'; Detail = "ccmsetup failed with exit code $($proc.ExitCode)"; Remediated = $false }
    }
    catch {
        return [pscustomobject]@{ Name = 'ClientInstall'; Status = 'Error'; Detail = "ccmsetup failed: $($_.Exception.Message)"; Remediated = $false }
    }
}

#endregion

#region WMI repair

function Repair-ClientHealthWMI {
    <#
    .SYNOPSIS
        Repairs a corrupt WMI repository.
    .DESCRIPTION
        Stops the Winmgmt service, runs winmgmt /salvagerepository, and restarts
        the service. Returns a structured result.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    try {
        Stop-Service -Name Winmgmt -Force -ErrorAction Stop
        $null = & winmgmt /salvagerepository 2>$null
        Start-Service -Name Winmgmt -ErrorAction Stop
        return [pscustomobject]@{ Name = 'WMI'; Status = 'Remediated'; Detail = 'WMI repository salvaged'; Remediated = $true }
    }
    catch {
        try { Start-Service -Name Winmgmt -ErrorAction SilentlyContinue } catch { }
        return [pscustomobject]@{ Name = 'WMI'; Status = 'Error'; Detail = "WMI repair failed: $($_.Exception.Message)"; Remediated = $false }
    }
}

#endregion

#region Admin share

function Test-ClientHealthAdminShare {
    <#
    .SYNOPSIS
        Checks for the presence of the C$ admin share.
    .DESCRIPTION
        Returns OK if the admin share exists. If remediation is enabled and the
        share is missing, recreates it.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $false)][bool]$Fix = $false
    )

    $share = Get-CimInstance -ClassName Win32_Share -Filter "Name='C$'" -ErrorAction SilentlyContinue

    if ($null -ne $share) {
        return [pscustomobject]@{ Name = 'AdminShare'; Status = 'OK'; Detail = 'C$ admin share present'; Remediated = $false }
    }

    if (-not $Fix) {
        return [pscustomobject]@{ Name = 'AdminShare'; Status = 'Warning'; Detail = 'C$ admin share missing; remediation disabled'; Remediated = $false }
    }

    try {
        $null = New-CimInstance -ClassName Win32_Share -Property @{
            Name = 'C$'; Path = "$env:SystemDrive\"; Type = 0
        } -ErrorAction Stop
        return [pscustomobject]@{ Name = 'AdminShare'; Status = 'Remediated'; Detail = 'C$ admin share recreated'; Remediated = $true }
    }
    catch {
        return [pscustomobject]@{ Name = 'AdminShare'; Status = 'Error'; Detail = "Failed to create admin share: $($_.Exception.Message)"; Remediated = $false }
    }
}

#endregion

#region Reboot application

function Invoke-ClientHealthRebootApplication {
    <#
    .SYNOPSIS
        Launches the configured reboot application.
    .DESCRIPTION
        Used when a pending reboot has exceeded the max reboot days. Launches
        the configured application (e.g. a reboot tool) for the user.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][string]$Application
    )

    if ([string]::IsNullOrWhiteSpace($Application)) {
        return [pscustomobject]@{ Name = 'RebootApplication'; Status = 'Skipped'; Detail = 'No reboot application configured'; Remediated = $false }
    }

    try {
        $null = Start-Process -FilePath $Application
        return [pscustomobject]@{ Name = 'RebootApplication'; Status = 'Remediated'; Detail = "Launched $Application"; Remediated = $true }
    }
    catch {
        return [pscustomobject]@{ Name = 'RebootApplication'; Status = 'Error'; Detail = "Failed to launch $Application : $($_.Exception.Message)"; Remediated = $false }
    }
}

#endregion

#region Software metering

function Test-ClientHealthSoftwareMetering {
    <#
    .SYNOPSIS
        Checks the software metering prep driver and installs it if missing.
    .DESCRIPTION
        Verifies the SWMTRP driver is present. If missing and remediation is
        enabled, installs the driver from the client directory.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $false)][bool]$Fix = $false
    )

    $driver = Get-CimInstance -ClassName Win32_SystemDriver -Filter "Name='SWMTRP'" -ErrorAction SilentlyContinue

    if ($null -ne $driver) {
        return [pscustomobject]@{ Name = 'SoftwareMetering'; Status = 'OK'; Detail = 'SWMTRP driver present'; Remediated = $false }
    }

    if (-not $Fix) {
        return [pscustomobject]@{ Name = 'SoftwareMetering'; Status = 'Warning'; Detail = 'SWMTRP driver missing; remediation disabled'; Remediated = $false }
    }

    try {
        $logDir = Get-ClientHealthCCMLogDirectory
        $ccmDir = Split-Path -Parent $logDir
        $driverPath = Join-Path $ccmDir 'SWMTRP.inf'
        if (-not (Test-Path -LiteralPath $driverPath)) {
            return [pscustomobject]@{ Name = 'SoftwareMetering'; Status = 'Error'; Detail = "SWMTRP.inf not found at $driverPath"; Remediated = $false }
        }
        $null = & pnputil.exe /add-driver $driverPath /install 2>$null
        return [pscustomobject]@{ Name = 'SoftwareMetering'; Status = 'Remediated'; Detail = 'SWMTRP driver installed'; Remediated = $true }
    }
    catch {
        return [pscustomobject]@{ Name = 'SoftwareMetering'; Status = 'Error'; Detail = "Failed to install SWMTRP driver: $($_.Exception.Message)"; Remediated = $false }
    }
}

#endregion

#region Compliance state

function Invoke-ClientHealthRefreshComplianceState {
    <#
    .SYNOPSIS
        Refreshes the client compliance state.
    .DESCRIPTION
        Uses the UpdatesStore COM object to refresh server compliance state.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    try {
        $store = New-Object -ComObject 'Microsoft.CCM.UpdatesStore'
        $store.RefreshServerComplianceState()
        return [pscustomobject]@{ Name = 'RefreshComplianceState'; Status = 'Remediated'; Detail = 'Compliance state refreshed'; Remediated = $true }
    }
    catch {
        return [pscustomobject]@{ Name = 'RefreshComplianceState'; Status = 'Error'; Detail = "Failed to refresh compliance state: $($_.Exception.Message)"; Remediated = $false }
    }
}

#endregion

#region SMSTS manager & ccmeval

function Invoke-ClientHealthSMSTSMgr {
    <#
    .SYNOPSIS
        Restarts the SMSTSMgr service.
    .DESCRIPTION
        Stops and restarts the SMS Task Sequence Manager service to clear stuck
        task sequence state.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    try {
        Restart-Service -Name SMSTSMgr -Force -ErrorAction Stop
        return [pscustomobject]@{ Name = 'SMSTSMgr'; Status = 'Remediated'; Detail = 'SMSTSMgr service restarted'; Remediated = $true }
    }
    catch {
        return [pscustomobject]@{ Name = 'SMSTSMgr'; Status = 'Error'; Detail = "Failed to restart SMSTSMgr: $($_.Exception.Message)"; Remediated = $false }
    }
}

function Invoke-ClientHealthCcmeval {
    <#
    .SYNOPSIS
        Runs the ConfigMgr client evaluation tool (ccmeval).
    .DESCRIPTION
        Launches ccmeval.exe to evaluate and repair client health.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $ccmeval = Join-Path $env:WinDir 'CCM\ccmeval.exe'
    if (-not (Test-Path -LiteralPath $ccmeval)) {
        return [pscustomobject]@{ Name = 'Ccmeval'; Status = 'Skipped'; Detail = 'ccmeval.exe not found'; Remediated = $false }
    }

    try {
        $proc = Start-Process -FilePath $ccmeval -ArgumentList @('-r') -Wait -PassThru
        return [pscustomobject]@{ Name = 'Ccmeval'; Status = 'Remediated'; Detail = "ccmeval completed (exit $($proc.ExitCode))"; Remediated = $true }
    }
    catch {
        return [pscustomobject]@{ Name = 'Ccmeval'; Status = 'Error'; Detail = "ccmeval failed: $($_.Exception.Message)"; Remediated = $false }
    }
}

#endregion

#region Cache cleanup

function Remove-ClientHealthOrphanedCache {
    <#
    .SYNOPSIS
        Removes orphaned ConfigMgr client cache content.
    .DESCRIPTION
        Deletes cache folders that are no longer referenced by active content
        (orphaned data) to free disk space.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    try {
        $ui = New-Object -ComObject 'UIResource.UIResourceMgr'
        $cache = $ui.GetCacheInfo()
        $removed = 0
        foreach ($item in $cache.GetCacheElements()) {
            if ($item.ContentId -eq '{00000000-0000-0000-0000-000000000000}') {
                $cache.DeleteCacheElement($item.CacheElementId)
                $removed++
            }
        }
        return [pscustomobject]@{ Name = 'CacheCleanup'; Status = 'Remediated'; Detail = "Removed $removed orphaned cache element(s)"; Remediated = $true }
    }
    catch {
        return [pscustomobject]@{ Name = 'CacheCleanup'; Status = 'Error'; Detail = "Failed to clean cache: $($_.Exception.Message)"; Remediated = $false }
    }
}

#endregion
