# Private\Configuration.ps1
# Typed configuration model for ConfigMgr Client Health.
#
# The original tool parsed config.xml with dozens of ad-hoc Get-XMLConfig*
# functions that returned strings and silently returned $null when a node was
# missing. This modern version deserializes the XML into a strongly-typed
# object graph with defaults, so every consumer gets a typed value and missing
# nodes fall back to sane defaults instead of $null.

#region Configuration classes

class ClientHealthClientConfig {
    [string]   $Version
    [string]   $SiteCode
    [string]   $Domain
    [bool]     $AutoUpgrade
    [string]   $Share
    [string[]] $InstallProperties
    [int]      $MaxLogSizeKB
    [int]      $MaxLogHistory
    [bool]     $MaxLogSizeEnabled
    [string]   $CacheSize
    [bool]     $CacheSizeEnabled
    [bool]     $CacheDeleteOrphanedData
}

class ClientHealthServiceConfig {
    [string] $Name
    [string] $StartupType
    [string] $State
    [int]    $UptimeDays
}

class ClientHealthOptionConfig {
    [bool]   $UpdatesEnabled
    [string] $UpdatesShare
    [bool]   $UpdatesFix
    [bool]   $DNSCheckEnabled
    [bool]   $DNSCheckFix
    [bool]   $CcmSQLCELogEnabled
    [bool]   $DriversEnabled
    [bool]   $PatchLevelEnabled
    [int]    $OSDiskFreeSpacePercent
    [bool]   $HardwareInventoryEnabled
    [bool]   $HardwareInventoryFix
    [int]    $HardwareInventoryDays
    [bool]   $SoftwareMeteringEnabled
    [bool]   $SoftwareMeteringFix
    [bool]   $BITSCheckEnabled
    [bool]   $BITSCheckFix
    [bool]   $ClientSettingsCheckEnabled
    [bool]   $ClientSettingsCheckFix
    [bool]   $WMIEnabled
    [bool]   $WMIRepairEnabled
    [bool]   $RefreshComplianceStateEnabled
    [int]    $RefreshComplianceStateDays
    [bool]   $PendingRebootEnabled
    [bool]   $PendingRebootStartRebootApplication
    [int]    $MaxRebootDays
    [string] $RebootApplication
    [bool]   $RebootApplicationEnabled
}

class ClientHealthRemediationConfig {
    [bool] $AdminShare
    [bool] $ClientProvisioningMode
    [bool] $ClientStateMessages
    [bool] $ClientWUAHandler
    [int]  $ClientWUAHandlerDays
    [bool] $ClientCertificate
}

class ClientHealthLoggingConfig {
    [bool]   $LocalLogFileEnabled
    [string] $LocalFilesPath
    [bool]   $FileShareEnabled
    [string] $FileShare
    [string] $Level
    [string] $TimeFormat
    [int]    $MaxHistory
    [bool]   $SQLEnabled
    [string] $SQLServer
    [string] $SQLDatabase
}

class ClientHealthConfig {
    [ClientHealthClientConfig]      $Client
    [ClientHealthServiceConfig[]]   $Services
    [ClientHealthOptionConfig]      $Option
    [ClientHealthRemediationConfig] $Remediation
    [ClientHealthLoggingConfig]     $Logging
    [string]                        $SourcePath
}

#endregion

#region Public config accessors

function Get-ClientHealthConfig {
    <#
    .SYNOPSIS
        Loads and validates a ConfigMgr Client Health configuration file into a typed object.
    .DESCRIPTION
        Reads the XML configuration file and returns a strongly-typed ClientHealthConfig
        object. Missing optional nodes fall back to defaults. Throws on invalid XML or
        missing required nodes.
    .PARAMETER Path
        Path to the configuration XML file.
    .EXAMPLE
        $config = Get-ClientHealthConfig -Path .\config.xml
    #>
    [CmdletBinding()]
    [OutputType([ClientHealthConfig])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Configuration file not found: $Path"
    }

    try {
        [xml]$xml = Get-Content -LiteralPath $Path -Raw
    }
    catch {
        throw "Configuration file '$Path' is not valid XML: $($_.Exception.Message)"
    }

    $config = [ClientHealthConfig]::new()
    $config.SourcePath = $Path

    # --- Client ---
    $client = $xml.Configuration.Client
    $cc = [ClientHealthClientConfig]::new()
    $cc.Version = [string]$client.Version
    $cc.SiteCode = [string]$client.SiteCode
    $cc.Domain = [string]$client.Domain
    $cc.AutoUpgrade = [bool]::Parse([string]$client.AutoUpgrade)
    $cc.Share = [string]$client.Share
    $cc.InstallProperties = @($client.ClientInstallProperty | ForEach-Object { [string]$_ })
    $cc.MaxLogSizeKB = [int]$client.Log.MaxLogSize
    $cc.MaxLogHistory = [int]$client.Log.MaxLogHistory
    $cc.MaxLogSizeEnabled = [bool]::Parse([string]$client.Log.Enable)
    $cc.CacheSize = [string]$client.CacheSize.Value
    $cc.CacheSizeEnabled = [bool]::Parse([string]$client.CacheSize.Enable)
    $cc.CacheDeleteOrphanedData = [bool]::Parse([string]$client.CacheSize.DeleteOrphanedData)
    $config.Client = $cc

    # --- Services ---
    $services = @()
    foreach ($svc in $xml.Configuration.Service) {
        $s = [ClientHealthServiceConfig]::new()
        $s.Name = [string]$svc.Name
        $s.StartupType = [string]$svc.StartupType
        $s.State = [string]$svc.State
        $s.UptimeDays = if ($null -ne $svc.Uptime) { [int]$svc.Uptime } else { 0 }
        $services += $s
    }
    $config.Services = $services

    # --- Option ---
    $opt = $xml.Configuration.Option
    $o = [ClientHealthOptionConfig]::new()
    $o.UpdatesEnabled = [bool]::Parse([string](Get-NodeValue $opt 'Updates' 'Enable' 'False'))
    $o.UpdatesShare = [string](Get-NodeValue $opt 'Updates' 'Share' '')
    $o.UpdatesFix = [bool]::Parse([string](Get-NodeValue $opt 'Updates' 'Fix' 'False'))
    $o.DNSCheckEnabled = [bool]::Parse([string](Get-NodeValue $opt 'DNSCheck' 'Enable' 'False'))
    $o.DNSCheckFix = [bool]::Parse([string](Get-NodeValue $opt 'DNSCheck' 'Fix' 'False'))
    $o.CcmSQLCELogEnabled = [bool]::Parse([string](Get-NodeValue $opt 'CcmSQLCELog' 'Enable' 'False'))
    $o.DriversEnabled = [bool]::Parse([string](Get-NodeValue $opt 'Drivers' 'Enable' 'False'))
    $o.PatchLevelEnabled = [bool]::Parse([string](Get-NodeValue $opt 'PatchLevel' 'Enable' 'False'))
    $o.OSDiskFreeSpacePercent = [int](Get-NodeValue $opt 'OSDiskFreeSpace' '#text' '10')
    $o.HardwareInventoryEnabled = [bool]::Parse([string](Get-NodeValue $opt 'HardwareInventory' 'Enable' 'False'))
    $o.HardwareInventoryFix = [bool]::Parse([string](Get-NodeValue $opt 'HardwareInventory' 'Fix' 'False'))
    $o.HardwareInventoryDays = [int](Get-NodeValue $opt 'HardwareInventory' 'Days' '7')
    $o.SoftwareMeteringEnabled = [bool]::Parse([string](Get-NodeValue $opt 'SoftwareMetering' 'Enable' 'False'))
    $o.SoftwareMeteringFix = [bool]::Parse([string](Get-NodeValue $opt 'SoftwareMetering' 'Fix' 'False'))
    $o.BITSCheckEnabled = [bool]::Parse([string](Get-NodeValue $opt 'BITSCheck' 'Enable' 'False'))
    $o.BITSCheckFix = [bool]::Parse([string](Get-NodeValue $opt 'BITSCheck' 'Fix' 'False'))
    $o.ClientSettingsCheckEnabled = [bool]::Parse([string](Get-NodeValue $opt 'ClientSettingsCheck' 'Enable' 'False'))
    $o.ClientSettingsCheckFix = [bool]::Parse([string](Get-NodeValue $opt 'ClientSettingsCheck' 'Fix' 'False'))
    $o.WMIEnabled = [bool]::Parse([string](Get-NodeValue $opt 'WMI' 'Enable' 'False'))
    $o.WMIRepairEnabled = [bool]::Parse([string](Get-NodeValue $opt 'WMI' 'Fix' 'False'))
    $o.RefreshComplianceStateEnabled = [bool]::Parse([string](Get-NodeValue $opt 'RefreshComplianceState' 'Enable' 'False'))
    $o.RefreshComplianceStateDays = [int](Get-NodeValue $opt 'RefreshComplianceState' 'Days' '7')
    $o.PendingRebootEnabled = [bool]::Parse([string](Get-NodeValue $opt 'PendingReboot' 'Enable' 'False'))
    $o.PendingRebootStartRebootApplication = [bool]::Parse([string](Get-NodeValue $opt 'PendingReboot' 'StartRebootApplication' 'False'))
    $o.MaxRebootDays = [int](Get-NodeValue $opt 'MaxRebootDays' 'Days' '90')
    $o.RebootApplication = [string](Get-NodeValue $opt 'RebootApplication' 'Application' '')
    $o.RebootApplicationEnabled = [bool]::Parse([string](Get-NodeValue $opt 'RebootApplication' 'Enable' 'False'))
    $config.Option = $o

    # --- Remediation ---
    $rem = $xml.Configuration.Remediation
    $r = [ClientHealthRemediationConfig]::new()
    $r.AdminShare = [bool]::Parse([string](Get-NodeValue $rem 'AdminShare' 'Fix' 'False'))
    $r.ClientProvisioningMode = [bool]::Parse([string](Get-NodeValue $rem 'ClientProvisioningMode' 'Fix' 'False'))
    $r.ClientStateMessages = [bool]::Parse([string](Get-NodeValue $rem 'ClientStateMessages' 'Fix' 'False'))
    $r.ClientWUAHandler = [bool]::Parse([string](Get-NodeValue $rem 'ClientWUAHandler' 'Fix' 'False'))
    $r.ClientWUAHandlerDays = [int](Get-NodeValue $rem 'ClientWUAHandler' 'Days' '7')
    $r.ClientCertificate = [bool]::Parse([string](Get-NodeValue $rem 'ClientCertificate' 'Fix' 'False'))
    $config.Remediation = $r

    # --- Logging ---
    $log = $xml.Configuration.Log
    $l = [ClientHealthLoggingConfig]::new()
    $l.LocalLogFileEnabled = [bool]::Parse([string](Get-NodeValue $log 'File' 'LocalLogFile' 'False'))
    $l.LocalFilesPath = [string](Get-NodeValue $log 'File' 'LocalFilesPath' "$env:SystemDrive\ClientHealth")
    $l.FileShareEnabled = [bool]::Parse([string](Get-NodeValue $log 'File' 'Enable' 'False'))
    $l.FileShare = [string](Get-NodeValue $log 'File' 'Share' '')
    $l.Level = [string](Get-NodeValue $log 'File' 'Level' 'Full')
    $l.TimeFormat = [string](Get-NodeValue $log 'Time' 'Format' 'ClientLocal')
    $l.MaxHistory = [int](Get-NodeValue $log 'File' 'MaxLogHistory' '10')
    $l.SQLEnabled = [bool]::Parse([string](Get-NodeValue $log 'SQL' 'Enable' 'False'))
    $l.SQLServer = [string](Get-NodeValue $log 'SQL' 'Server' '')
    $l.SQLDatabase = [string](Get-NodeValue $log 'SQL' 'Database' 'ClientHealth')
    $config.Logging = $l

    return $config
}

function Test-ClientHealthConfig {
    <#
    .SYNOPSIS
        Validates a ConfigMgr Client Health configuration file.
    .DESCRIPTION
        Returns $true if the file is valid XML and contains the required
        Configuration/Client node, otherwise $false.
    .PARAMETER Path
        Path to the configuration XML file.
    .EXAMPLE
        Test-ClientHealthConfig -Path .\config.xml
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    try {
        $null = Get-ClientHealthConfig -Path $Path
        return $true
    }
    catch {
        Write-Warning "Config validation failed: $($_.Exception.Message)"
        return $false
    }
}

#endregion

#region Private helpers

function Get-NodeValue {
    <#
    .SYNOPSIS
        Safely reads an attribute or element value from an XML node collection.
    .DESCRIPTION
        Given a parent node, finds the child element with the given name and
        returns the requested attribute, '#text' (element text), or a default.
        Returns the default when the node or attribute is missing.
    #>
    param(
        [Parameter(Mandatory = $true)]$Parent,
        [Parameter(Mandatory = $true)][string]$ElementName,
        [Parameter(Mandatory = $true)][string]$Attribute,
        [Parameter(Mandatory = $false)]$Default = $null
    )

    if ($null -eq $Parent) { return $Default }

    $node = $Parent | Where-Object { $_.Name -eq $ElementName } | Select-Object -First 1
    if ($null -eq $node) { return $Default }

    if ($Attribute -eq '#text') {
        return [string]$node.'#text'
    }

    $attr = $node.Attributes | Where-Object { $_.Name -eq $Attribute } | Select-Object -First 1
    if ($null -ne $attr) { return [string]$attr.Value }

    return $Default
}

#endregion
