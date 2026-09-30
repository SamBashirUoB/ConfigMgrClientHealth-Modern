# Public\Get-ClientHealthReport.ps1
# Returns the health report as a formatted object / CSV.

function Get-ClientHealthReport {
    <#
    .SYNOPSIS
        Formats a health-check log object as a report.
    .DESCRIPTION
        Returns the log object as a PSCustomObject suitable for CSV export or
        display. Optionally writes it to a CSV file.
    .PARAMETER Log
        The health-check log object from Invoke-ClientHealthCheck.
    .PARAMETER Path
        Optional path to write a CSV report to.
    .EXAMPLE
        $log = Invoke-ClientHealthCheck -ConfigPath .\config.xml
        Get-ClientHealthReport -Log $log -Path .\report.csv
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $Log,

        [Parameter(Mandatory = $false)]
        [string]$Path
    )

    process {
        $report = [pscustomobject]@{
            Hostname              = $Log.Hostname
            Operatingsystem       = $Log.Operatingsystem
            Architecture          = $Log.Architecture
            Build                 = $Log.Build
            Manufacturer          = $Log.Manufacturer
            Model                 = $Log.Model
            InstallDate           = $Log.InstallDate
            OSUpdates             = $Log.OSUpdates
            LastLoggedOnUser      = $Log.LastLoggedOnUser
            ClientVersion         = $Log.ClientVersion
            PSVersion             = $Log.PSVersion
            PSBuild               = $Log.PSBuild
            Sitecode              = $Log.Sitecode
            Domain                = $Log.Domain
            MaxLogSize            = $Log.MaxLogSize
            MaxLogHistory         = $Log.MaxLogHistory
            CacheSize             = $Log.CacheSize
            ClientCertificate     = $Log.ClientCertificate
            ProvisioningMode      = $Log.ProvisioningMode
            DNS                   = $Log.DNS
            Drivers               = $Log.Drivers
            Updates               = $Log.Updates
            PendingReboot         = $Log.PendingReboot
            LastBootTime          = $Log.LastBootTime
            OSDiskFreeSpace       = $Log.OSDiskFreeSpace
            Services              = $Log.Services
            AdminShare            = $Log.AdminShare
            StateMessages         = $Log.StateMessages
            WUAHandler            = $Log.WUAHandler
            WMI                   = $Log.WMI
            RefreshComplianceState = $Log.RefreshComplianceState
            HWInventory           = $Log.HWInventory
            SWMetering            = $Log.SWMetering
            ClientSettings        = $Log.ClientSettings
            BITS                  = $Log.BITS
            PatchLevel            = $Log.PatchLevel
            ClientInstalledReason = $Log.ClientInstalledReason
            RebootApp             = $Log.RebootApp
            Version               = $Log.Version
            Timestamp             = $Log.Timestamp
            ClientInstalled       = $Log.ClientInstalled
        }

        if ($Path) {
            $report | Export-Csv -LiteralPath $Path -NoTypeInformation -Append
        }

        return $report
    }
}
