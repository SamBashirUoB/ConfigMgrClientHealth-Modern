# Public\Invoke-ClientHealthCheck.ps1
# Main entry point: runs all configured health checks and remediations.

function Invoke-ClientHealthCheck {
    <#
    .SYNOPSIS
        Runs the ConfigMgr Client Health checks and remediations.
    .DESCRIPTION
        Loads the configuration, runs each enabled health check, applies
        remediation where configured, and reports results to the local log,
        SQL database, and/or REST webservice as configured.
    .PARAMETER ConfigPath
        Path to the configuration XML file.
    .PARAMETER LogPath
        Optional override for the local log file path.
    .PARAMETER SkipRemediation
        Runs checks only; does not apply any remediation actions.
    .EXAMPLE
        Invoke-ClientHealthCheck -ConfigPath .\config.xml
    .EXAMPLE
        Invoke-ClientHealthCheck -ConfigPath .\config.xml -SkipRemediation
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$ConfigPath,

        [Parameter(Mandatory = $false)]
        [string]$LogPath,

        [Parameter(Mandatory = $false)]
        [switch]$SkipRemediation
    )

    # --- Load config ---
    $config = Get-ClientHealthConfig -Path $ConfigPath
    $log = New-ClientHealthLogObject

    # --- Determine log file ---
    if (-not $LogPath) {
        if ($config.Logging.LocalLogFileEnabled) {
            $LogPath = Join-Path $config.Logging.LocalFilesPath 'ClientHealth.log'
        }
        elseif ($config.Logging.FileShareEnabled) {
            $LogPath = Join-Path $config.Logging.FileShare 'ClientHealth.log'
        }
    }

    if ($LogPath) {
        Test-ClientHealthLogHistory -LogFile $LogPath -MaxHistory $config.Logging.MaxHistory
    }

    $fix = -not $SkipRemediation

    # --- Client install / version ---
    $clientResult = Resolve-ClientHealthClient `
        -Share $config.Client.Share `
        -SiteCode $config.Client.SiteCode `
        -Domain $config.Client.Domain `
        -MinimumVersion $config.Client.Version `
        -AutoUpgrade $config.Client.AutoUpgrade `
        -InstallProperties $config.Client.InstallProperties
    $log.ClientInstalled = $clientResult.Status
    $log.ClientInstalledReason = $clientResult.Detail

    # --- Client version & site code ---
    $ver = Test-ClientHealthClientVersion -MinimumVersion $config.Client.Version -AutoUpgrade $config.Client.AutoUpgrade
    $log.ClientVersion = (Get-ClientHealthClientVersion)
    $site = Test-ClientHealthSiteCode -ExpectedSiteCode $config.Client.SiteCode
    $log.Sitecode = (Get-ClientHealthSiteCode)

    # --- Cache size ---
    if ($config.Client.CacheSizeEnabled) {
        $cache = Test-ClientHealthCacheSize -ConfiguredCacheSize $config.Client.CacheSize -Fix ($fix -and $config.Client.CacheSizeEnabled)
        $log.CacheSize = $cache.Status
    }

    # --- Log size ---
    if ($config.Client.MaxLogSizeEnabled) {
        $logSize = Test-ClientHealthLogSize -MaxLogSizeKB $config.Client.MaxLogSizeKB -MaxLogHistory $config.Client.MaxLogHistory -Fix ($fix -and $config.Client.MaxLogSizeEnabled)
        $log.MaxLogSize = $logSize.Status
        $log.MaxLogHistory = $logSize.Status
    }

    # --- Local database ---
    $db = Test-ClientHealthLocalDatabase
    if ($db.Status -eq 'Error') {
        $log.ClientInstalled = 'Error'
        $log.ClientInstalledReason = 'Local database corrupt; client needs reinstall'
    }

    # --- WMI ---
    if ($config.Option.WMIEnabled) {
        $wmi = Test-ClientHealthWMI
        if ($wmi.Status -eq 'Error' -and $fix -and $config.Option.WMIRepairEnabled) {
            $wmi = Repair-ClientHealthWMI
        }
        $log.WMI = $wmi.Status
    }

    # --- CcmSQLCE log ---
    if ($config.Option.CcmSQLCELogEnabled) {
        $sqlce = Test-ClientHealthCcmSQLCELog
        if ($sqlce.Status -eq 'Error') {
            $log.ClientInstalled = 'Error'
            $log.ClientInstalledReason = 'CcmSQLCE.log indicates corrupt local database'
        }
    }

    # --- Provisioning mode ---
    if ($config.Remediation.ClientProvisioningMode) {
        $prov = Test-ClientHealthProvisioningMode -Fix ($fix -and $config.Remediation.ClientProvisioningMode)
        $log.ProvisioningMode = $prov.Status
    }

    # --- Services ---
    if ($config.Services.Count -gt 0) {
        $svcResults = Test-ClientHealthServices -Services $config.Services
        $log.Services = ($svcResults | ForEach-Object { "$($_.Name)=$($_.Status)" }) -join ';'
    }

    # --- Admin share ---
    if ($config.Remediation.AdminShare) {
        $share = Test-ClientHealthAdminShare -Fix ($fix -and $config.Remediation.AdminShare)
        $log.AdminShare = $share.Status
    }

    # --- DNS ---
    if ($config.Option.DNSCheckEnabled) {
        $dns = Test-ClientHealthDNS -Fix ($fix -and $config.Option.DNSCheckFix)
        $log.DNS = $dns.Status
    }

    # --- Drivers ---
    if ($config.Option.DriversEnabled) {
        $drv = Test-ClientHealthMissingDrivers
        $log.Drivers = $drv.Status
    }

    # --- Updates ---
    if ($config.Option.UpdatesEnabled) {
        $upd = Test-ClientHealthRequiredUpdates -UpdateShare $config.Option.UpdatesShare -Fix ($fix -and $config.Option.UpdatesFix)
        $log.Updates = $upd.Status
    }

    # --- Patch level ---
    if ($config.Option.PatchLevelEnabled) {
        $lastPatch = Get-ClientHealthLastInstalledPatch
        $log.PatchLevel = if ($null -eq $lastPatch) { 'Unknown' } else { $lastPatch.ToString('yyyy-MM-dd') }
    }

    # --- Pending reboot ---
    if ($config.Option.PendingRebootEnabled) {
        $reboot = Test-ClientHealthPendingReboot
        $log.PendingReboot = $reboot.Status
        if ($reboot.Status -eq 'Warning' -and $config.Option.RebootApplicationEnabled -and $fix) {
            $null = Invoke-ClientHealthRebootApplication -Application $config.Option.RebootApplication
            $log.RebootApp = 'Launched'
        }
    }

    # --- Hardware inventory ---
    if ($config.Option.HardwareInventoryEnabled) {
        $hw = Test-ClientHealthHardwareInventory -Days $config.Option.HardwareInventoryDays -Fix ($fix -and $config.Option.HardwareInventoryFix)
        $log.HWInventory = $hw.Status
    }

    # --- Software metering ---
    if ($config.Option.SoftwareMeteringEnabled) {
        $sw = Test-ClientHealthSoftwareMetering -Fix ($fix -and $config.Option.SoftwareMeteringFix)
        $log.SWMetering = $sw.Status
    }

    # --- BITS ---
    if ($config.Option.BITSCheckEnabled) {
        $bits = Test-ClientHealthBITS -Fix ($fix -and $config.Option.BITSCheckFix)
        $log.BITS = $bits.Status
    }

    # --- Client settings ---
    if ($config.Option.ClientSettingsCheckEnabled) {
        $cs = Test-ClientHealthClientSettings -Fix ($fix -and $config.Option.ClientSettingsCheckFix)
        $log.ClientSettings = $cs.Status
    }

    # --- State messages ---
    if ($config.Remediation.ClientStateMessages) {
        $sm = Test-ClientHealthStateMessages -Fix ($fix -and $config.Remediation.ClientStateMessages)
        $log.StateMessages = $sm.Status
    }

    # --- WUAHandler / registry.pol ---
    if ($config.Remediation.ClientWUAHandler) {
        $wua = Test-ClientHealthRegistryPol -Days $config.Remediation.ClientWUAHandlerDays -Fix ($fix -and $config.Remediation.ClientWUAHandler)
        $log.WUAHandler = $wua.Status
    }

    # --- Certificate ---
    if ($config.Remediation.ClientCertificate) {
        $cert = Test-ClientHealthCertificate -Fix ($fix -and $config.Remediation.ClientCertificate)
        $log.ClientCertificate = $cert.Status
    }

    # --- Refresh compliance state ---
    if ($config.Option.RefreshComplianceStateEnabled) {
        $rfc = Invoke-ClientHealthRefreshComplianceState
        $log.RefreshComplianceState = $rfc.Status
    }

    # --- OS disk free space ---
    $free = Get-ClientHealthOSDiskFreeSpacePercent
    $log.OSDiskFreeSpace = "$free%"

    # --- OS updates count ---
    try {
        $updates = @(Get-CimInstance -ClassName Win32_QuickFixEngineering -ErrorAction SilentlyContinue)
        $log.OSUpdates = $updates.Count
    }
    catch { }

    # --- Write local log ---
    if ($LogPath) {
        Write-ClientHealthLogObject -Log $log -LogFile $LogPath
    }

    # --- SQL reporting ---
    if ($config.Logging.SQLEnabled) {
        $null = Send-ClientHealthReportToSql -Log $log -Server $config.Logging.SQLServer -Database $config.Logging.SQLDatabase
    }

    # --- Webservice reporting ---
    if ($config.Logging.FileShareEnabled -and $config.Logging.FileShare -like 'http*') {
        $null = Send-ClientHealthReportToWebservice -Log $log -Uri $config.Logging.FileShare
    }

    return $log
}
