# Private\Helpers.ps1
# Shared helper functions: CIM-based system info, OS detection, registry
# helpers, and SCCM policy trigger codes.
#
# The original tool branched on $PowerShellVersion everywhere (WMI vs CIM).
# Modern Windows (and PowerShell 5.1+ / 7+) all support CIM, so this version
# uses CIM exclusively and drops the legacy WMI code paths.

#region System info

function Get-ClientHealthComputerInfo {
    <#
    .SYNOPSIS
        Gathers basic computer information via CIM.
    .DESCRIPTION
        Returns a PSCustomObject with hostname, OS, architecture, build,
        manufacturer, model, install date, and last logged-on user.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem

    $model = $cs.Model
    if ($cs.Manufacturer -like 'Lenovo') {
        $model = (Get-CimInstance -ClassName Win32_ComputerSystemProduct).Version
    }

    $lastUser = $null
    try {
        $lastUser = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI' -ErrorAction Stop).LastLoggedOnUser
    }
    catch { }

    return [pscustomobject]@{
        Hostname       = $cs.Name
        Manufacturer   = $cs.Manufacturer
        Model          = $model
        OperatingSystem = $os.Caption
        Architecture   = $os.OSArchitecture
        Build          = $os.BuildNumber
        UBR            = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).UBR
        InstallDate    = $os.InstallDate
        LastBootTime   = $os.LastBootUpTime
        LastLoggedOnUser = $lastUser
        Domain         = $cs.Domain
    }
}

function Get-ClientHealthOSName {
    <#
    .SYNOPSIS
        Returns a normalized OS name (e.g. "Windows 10 22H2").
    .DESCRIPTION
        Maps the OS caption + build number to a normalized name used for
        update-share folder lookups. Handles localized captions.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $arch = ($os.OSArchitecture -replace '([^0-9])(\.*)', '') + '-Bit'

    $name = switch -Wildcard ($os.Caption) {
        '*Windows 7*'      { 'Windows 7 ' + $arch }
        '*Windows 8.1*'    { 'Windows 8.1 ' + $arch }
        '*Windows 10*'     { 'Windows 10 ' + $arch }
        '*Windows 11*'     { 'Windows 11 ' + $arch }
        '*Server 2008*'    { if ($os.Caption -like '*R2*') { 'Windows Server 2008 R2 ' + $arch } else { 'Windows Server 2008 ' + $arch } }
        '*Server 2012*'    { if ($os.Caption -like '*R2*') { 'Windows Server 2012 R2 ' + $arch } else { 'Windows Server 2012 ' + $arch } }
        '*Server 2016*'    { 'Windows Server 2016 ' + $arch }
        '*Server 2019*'    { 'Windows Server 2019 ' + $arch }
        '*Server 2022*'    { 'Windows Server 2022 ' + $arch }
        '*Server 2025*'    { 'Windows Server 2025 ' + $arch }
        default            { $os.Caption + ' ' + $arch }
    }

    # Append the Windows 10/11 feature update version from the build number.
    if ($os.Caption -like '*Windows 10*' -or $os.Caption -like '*Windows 11*') {
        $build = [int]$os.BuildNumber
        $version = switch ($build) {
            10240 { '1507' }; 10586 { '1511' }; 14393 { '1607' }; 15063 { '1703' }
            16299 { '1709' }; 17134 { '1803' }; 17763 { '1809' }; 18362 { '1903' }
            18363 { '1909' }; 19041 { '2004' }; 19042 { '20H2' }; 19043 { '21H1' }
            19044 { '21H2' }; 19045 { '22H2' }; 22000 { '21H2' }; 22621 { '22H2' }
            22631 { '23H2' }; 26100 { '24H2' }
            default { 'Insider Preview' }
        }
        $name = $name + ' ' + $version
    }

    return $name
}

function Get-ClientHealthOSDiskFreeSpacePercent {
    <#
    .SYNOPSIS
        Returns the free space percentage of the system drive.
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param()

    $drive = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'"
    if ($null -eq $drive -or $drive.Size -eq 0) { return 0 }
    return [math]::Round(($drive.FreeSpace / $drive.Size) * 100, 2)
}

#endregion

#region Registry helpers

function Get-ClientHealthRegistryValue {
    <#
    .SYNOPSIS
        Reads a registry value, returning $null if missing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name
    )
    try {
        return (Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop).$Name
    }
    catch {
        return $null
    }
}

function Set-ClientHealthRegistryValue {
    <#
    .SYNOPSIS
        Writes a registry value, creating the key if needed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]$Value,
        [ValidateSet('String', 'ExpandString', 'Binary', 'DWord', 'MultiString', 'Qword')]
        [string]$PropertyType = 'String'
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        $null = New-Item -Path $Path -Force
    }
    $null = New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $PropertyType -Force
}

#endregion

#region SCCM policy trigger codes

function Get-ClientHealthPolicyTrigger {
    <#
    .SYNOPSIS
        Returns the schedule GUID for a named SCCM client policy trigger.
    .DESCRIPTION
        Maps friendly trigger names to the well-known schedule IDs used by
        Invoke-CimMethod TriggerSchedule on the SMS_Client class.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet(
            'HardwareInventory', 'SoftwareInventory', 'DiscoveryInventory',
            'RequestMachineAssignments', 'EvaluateMachinePolicies',
            'RefreshDefaultMP', 'SourceUpdateMessage', 'SendUnsentStateMessages',
            'ScanByUpdateSource', 'UpdateStorePolicy', 'MachineEvaluation'
        )]
        [string]$Name
    )

    $triggers = @{
        HardwareInventory        = '{00000000-0000-0000-0000-000000000001}'
        SoftwareInventory        = '{00000000-0000-0000-0000-000000000002}'
        DiscoveryInventory       = '{00000000-0000-0000-0000-000000000003}'
        RequestMachineAssignments = '{00000000-0000-0000-0000-000000000021}'
        EvaluateMachinePolicies  = '{00000000-0000-0000-0000-000000000022}'
        RefreshDefaultMP         = '{00000000-0000-0000-0000-000000000023}'
        SourceUpdateMessage      = '{00000000-0000-0000-0000-000000000032}'
        SendUnsentStateMessages  = '{00000000-0000-0000-0000-000000000111}'
        ScanByUpdateSource       = '{00000000-0000-0000-0000-000000000113}'
        UpdateStorePolicy        = '{00000000-0000-0000-0000-000000000114}'
        MachineEvaluation        = '{00000000-0000-0000-0000-000000000022}'
    }

    return $triggers[$Name]
}

function Invoke-ClientHealthPolicyTrigger {
    <#
    .SYNOPSIS
        Triggers an SCCM client policy schedule via CIM.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Name
    )
    $scheduleId = Get-ClientHealthPolicyTrigger -Name $Name
    try {
        $null = Invoke-CimMethod -Namespace 'root\ccm' -ClassName 'SMS_Client' `
            -MethodName 'TriggerSchedule' -Arguments @{ sScheduleID = $scheduleId } `
            -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed to trigger SCCM policy '$Name' ($scheduleId): $($_.Exception.Message)"
    }
}

#endregion

#region Misc helpers

function Get-ClientHealthServiceUptimeDays {
    <#
    .SYNOPSIS
        Returns the uptime in days for a service.
    .DESCRIPTION
        Uses the service process start time (CIM) as a reliable cross-version
        method. Returns [int]::MaxValue if it cannot be determined.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)][string]$Name
    )

    try {
        $svc = Get-CimInstance -ClassName Win32_Service -Filter "Name='$Name'" -ErrorAction Stop
        if ($null -eq $svc -or $svc.ProcessId -eq 0) { return [int]::MaxValue }
        $proc = Get-Process -Id $svc.ProcessId -ErrorAction Stop
        return [math]::Max(0, [int](New-TimeSpan -Start $proc.StartTime -End (Get-Date)).TotalDays)
    }
    catch {
        return [int]::MaxValue
    }
}

function Test-ClientHealthIsAdministrator {
    <#
    .SYNOPSIS
        Returns $true if the current session is running elevated.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-ClientHealthInTaskSequence {
    <#
    .SYNOPSIS
        Returns $true if a ConfigMgr task sequence is currently running.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    try {
        $tsenv = New-Object -ComObject Microsoft.SMS.TSEnvironment -ErrorAction Stop
        return $null -ne $tsenv
    }
    catch {
        return $false
    }
}

#endregion
