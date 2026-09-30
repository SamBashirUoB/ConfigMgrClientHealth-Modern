# Public\New-ClientHealthLogObject.ps1
# Creates the health-check log object (the full report of all check results).

function New-ClientHealthLogObject {
    <#
    .SYNOPSIS
        Creates a new ConfigMgr Client Health log object.
    .DESCRIPTION
        Returns a PSCustomObject with all the fields the original tool reported,
        pre-populated with computer info and empty check results. The main runner
        fills in each check result.
    .EXAMPLE
        $log = New-ClientHealthLogObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $info = Get-ClientHealthComputerInfo
    $ps = $PSVersionTable

    return [pscustomobject]@{
        Hostname              = $info.Hostname
        Operatingsystem       = $info.OperatingSystem
        Architecture          = $info.Architecture
        Build                 = $info.Build
        Manufacturer          = $info.Manufacturer
        Model                 = $info.Model
        InstallDate           = $info.InstallDate
        OSUpdates             = ''
        LastLoggedOnUser      = $info.LastLoggedOnUser
        ClientVersion         = (Get-ClientHealthClientVersion)
        PSVersion             = [string]$ps.PSVersion
        PSBuild               = [string]$ps.BuildVersion
        Sitecode              = (Get-ClientHealthSiteCode)
        Domain                = $info.Domain
        MaxLogSize            = ''
        MaxLogHistory         = ''
        CacheSize             = ''
        ClientCertificate     = ''
        ProvisioningMode      = ''
        DNS                   = ''
        Drivers               = ''
        Updates               = ''
        PendingReboot         = ''
        LastBootTime          = $info.LastBootTime
        OSDiskFreeSpace       = ''
        Services              = ''
        AdminShare            = ''
        StateMessages         = ''
        WUAHandler            = ''
        WMI                   = ''
        RefreshComplianceState = ''
        HWInventory           = ''
        SWMetering            = ''
        ClientSettings        = ''
        BITS                  = ''
        PatchLevel            = ''
        ClientInstalledReason = ''
        RebootApp             = ''
        Version               = '1.0.0'
        Timestamp             = (Get-Date)
        ClientInstalled       = ''
    }
}
