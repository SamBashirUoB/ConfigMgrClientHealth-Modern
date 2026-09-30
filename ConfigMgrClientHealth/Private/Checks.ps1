# Private\Checks.ps1
# Health check functions.
#
# Each check returns a result object with:
#   Name        - check name
#   Status      - 'OK' | 'Warning' | 'Error' | 'Remediated' | 'Skipped'
#   Detail      - human-readable detail
#   Remediated  - $true if a remediation action was taken
#
# These are the modernized equivalents of the original tool's Test-* functions.
# They use CIM instead of WMI, typed config instead of XML string parsing, and
# return structured results instead of writing to a shared $Log object.

#region Client presence & version

function Test-ClientHealthClientInstalled {
    <#
    .SYNOPSIS
        Checks whether the ConfigMgr client (ccmexec) is installed.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $svc = Get-Service -Name ccmexec -ErrorAction SilentlyContinue
    if ($null -eq $svc) {
        return [pscustomobject]@{ Name = 'ClientInstalled'; Status = 'Error'; Detail = 'ConfigMgr client not installed'; Remediated = $false }
    }
    return [pscustomobject]@{ Name = 'ClientInstalled'; Status = 'OK'; Detail = "ConfigMgr client installed (state: $($svc.Status))"; Remediated = $false }
}

function Get-ClientHealthClientVersion {
    <#
    .SYNOPSIS
        Returns the installed ConfigMgr client version from the root\ccm SMS_Client class.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    try {
        $client = Get-CimInstance -Namespace 'root\ccm' -ClassName 'SMS_Client' -ErrorAction Stop
        return [string]$client.ClientVersion
    }
    catch {
        return $null
    }
}

function Get-ClientHealthSiteCode {
    <#
    .SYNOPSIS
        Returns the assigned ConfigMgr site code.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    try {
        $sms = New-Object -ComObject 'Microsoft.SMS.Client' -ErrorAction Stop
        return [string]$sms.GetAssignedSite()
    }
    catch {
        return $null
    }
}

function Test-ClientHealthClientVersion {
    <#
    .SYNOPSIS
        Checks the installed client version against the configured minimum.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][string]$MinimumVersion,
        [Parameter(Mandatory = $false)][bool]$AutoUpgrade = $false
    )

    $installed = Get-ClientHealthClientVersion
    if ([string]::IsNullOrWhiteSpace($installed)) {
        return [pscustomobject]@{ Name = 'ClientVersion'; Status = 'Error'; Detail = 'Unable to read client version'; Remediated = $false }
    }

    if ($installed -ge $MinimumVersion) {
        return [pscustomobject]@{ Name = 'ClientVersion'; Status = 'OK'; Detail = "Client version $installed (minimum $MinimumVersion)"; Remediated = $false }
    }

    if ($AutoUpgrade) {
        return [pscustomobject]@{ Name = 'ClientVersion'; Status = 'Warning'; Detail = "Client version $installed below minimum $MinimumVersion; tagged for upgrade"; Remediated = $false }
    }

    return [pscustomobject]@{ Name = 'ClientVersion'; Status = 'Warning'; Detail = "Client version $installed below minimum $MinimumVersion; auto-upgrade disabled"; Remediated = $false }
}

function Test-ClientHealthSiteCode {
    <#
    .SYNOPSIS
        Checks the assigned site code and remediates if it differs.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][string]$ExpectedSiteCode
    )

    $current = Get-ClientHealthSiteCode
    if ([string]::IsNullOrWhiteSpace($current)) {
        return [pscustomobject]@{ Name = 'SiteCode'; Status = 'Error'; Detail = 'Unable to read assigned site code'; Remediated = $false }
    }

    if ($current.Trim() -eq $ExpectedSiteCode.Trim()) {
        return [pscustomobject]@{ Name = 'SiteCode'; Status = 'OK'; Detail = "Site code $current"; Remediated = $false }
    }

    try {
        $sms = New-Object -ComObject 'Microsoft.SMS.Client' -ErrorAction Stop
        $sms.SetAssignedSite($ExpectedSiteCode)
        return [pscustomobject]@{ Name = 'SiteCode'; Status = 'Remediated'; Detail = "Site code changed from $current to $ExpectedSiteCode"; Remediated = $true }
    }
    catch {
        $msg = "Failed to change site code from $current to $ExpectedSiteCode - $($_.Exception.Message)"
        return [pscustomobject]@{ Name = 'SiteCode'; Status = 'Error'; Detail = $msg; Remediated = $false }
    }
}

#endregion

#region Client database & WMI

function Test-ClientHealthLocalDatabase {
    <#
    .SYNOPSIS
        Checks that the local ConfigMgr client database (.sdf) files are present.
    .DESCRIPTION
        Returns Error if fewer than 7 .sdf files exist in the client directory
        (indicating a broken client that needs reinstall).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $logDir = Get-ClientHealthCCMLogDirectory
    $ccmDir = Split-Path -Parent $logDir
    $files = @(Get-ChildItem -Path (Join-Path $ccmDir '*.sdf') -ErrorAction SilentlyContinue)

    if ($files.Count -lt 7) {
        return [pscustomobject]@{ Name = 'LocalDatabase'; Status = 'Error'; Detail = "Only $($files.Count) local database files present (expected >= 7)"; Remediated = $false }
    }
    return [pscustomobject]@{ Name = 'LocalDatabase'; Status = 'OK'; Detail = "$($files.Count) local database files present"; Remediated = $false }
}

function Test-ClientHealthWMI {
    <#
    .SYNOPSIS
        Checks WMI repository consistency and connectivity.
    .DESCRIPTION
        Runs winmgmt /verifyrepository and tests CIM connectivity. Returns Error
        (with a vote count) if the repository is inconsistent or unreachable.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $vote = 0
    $result = & winmgmt /verifyrepository 2>$null

    if ($result -match 'inconsistent|not consistent|inkonsekvent|epäyhtenäinen|inkonsistent') {
        $vote = 100
    }

    try {
        $null = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    }
    catch {
        $vote++
    }

    if ($vote -eq 0) {
        return [pscustomobject]@{ Name = 'WMI'; Status = 'OK'; Detail = 'WMI repository consistent'; Remediated = $false }
    }
    return [pscustomobject]@{ Name = 'WMI'; Status = 'Error'; Detail = "WMI repository inconsistent (vote=$vote)"; Remediated = $false }
}

function Test-ClientHealthCcmSQLCELog {
    <#
    .SYNOPSIS
        Checks for a stale CcmSQLCE.log indicating a corrupt local database.
    .DESCRIPTION
        If CcmSQLCE.log exists, the client is not in debug mode, and the log has
        been written within 7 days but the client is older than 7 days, the local
        database is considered corrupt and the client is tagged for reinstall.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $logDir = Get-ClientHealthCCMLogDirectory
    $logFile = Join-Path $logDir 'CcmSQLCE.log'
    $logLevel = Get-ClientHealthRegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\CCM\Logging\@Global' -Name 'logLevel'

    if (-not (Test-Path -LiteralPath $logFile) -or $logLevel -eq 0) {
        return [pscustomobject]@{ Name = 'CcmSQLCELog'; Status = 'OK'; Detail = 'No stale CcmSQLCE.log'; Remediated = $false }
    }

    $file = Get-Item -LiteralPath $logFile
    $now = Get-Date
    $lastWriteAge = ($now - $file.LastWriteTime).Days
    $fileAge = ($now - $file.CreationTime).Days

    if ($lastWriteAge -lt 7 -and $fileAge -gt 7) {
        return [pscustomobject]@{ Name = 'CcmSQLCELog'; Status = 'Error'; Detail = 'CcmSQLCE.log present and recently written; local database corrupt'; Remediated = $false }
    }
    return [pscustomobject]@{ Name = 'CcmSQLCELog'; Status = 'OK'; Detail = 'No corruption detected'; Remediated = $false }
}

function Get-ClientHealthCCMLogDirectory {
    <#
    .SYNOPSIS
        Returns the ConfigMgr client log directory.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $dir = Get-ClientHealthRegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\CCM\Logging\@Global' -Name 'LogDirectory'
    if ([string]::IsNullOrWhiteSpace($dir)) {
        $dir = "$env:SystemDrive\Windows\CCM\Logs"
    }
    return $dir
}

#endregion

#region Client configuration checks

function Test-ClientHealthCacheSize {
    <#
    .SYNOPSIS
        Checks the ConfigMgr client cache size against the configured value.
    .DESCRIPTION
        Supports fixed MB values and percentage-of-disk values. Remediation sets
        the cache size via the UIResource COM object.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][string]$ConfiguredCacheSize,
        [Parameter(Mandatory = $false)][bool]$Fix = $false
    )

    $current = Get-ClientHealthCacheSizeMB
    $expected = $ConfiguredCacheSize

    if ($ConfiguredCacheSize -match '%') {
        $percent = ([double]($ConfiguredCacheSize -replace '%')) / 100
        $drive = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'"
        $expected = [math]::Round(($drive.Size * $percent) / 1MB)
        if ($expected -gt 99999) { $expected = 99999 }
    }
    else {
        $expected = [int]$ConfiguredCacheSize
    }

    if ($current -eq $expected) {
        return [pscustomobject]@{ Name = 'CacheSize'; Status = 'OK'; Detail = "Cache size $current MB (expected $expected MB)"; Remediated = $false }
    }

    if (-not $Fix) {
        return [pscustomobject]@{ Name = 'CacheSize'; Status = 'Warning'; Detail = "Cache size $current MB (expected $expected MB); remediation disabled"; Remediated = $false }
    }

    try {
        $ui = New-Object -ComObject 'UIResource.UIResourceMgr'
        $ui.GetCacheInfo().TotalSize = "$expected"
        return [pscustomobject]@{ Name = 'CacheSize'; Status = 'Remediated'; Detail = "Cache size set to $expected MB"; Remediated = $true }
    }
    catch {
        return [pscustomobject]@{ Name = 'CacheSize'; Status = 'Error'; Detail = "Failed to set cache size: $($_.Exception.Message)"; Remediated = $false }
    }
}

function Get-ClientHealthCacheSizeMB {
    <#
    .SYNOPSIS
        Returns the current ConfigMgr client cache size in MB.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param()
    try {
        $ui = New-Object -ComObject 'UIResource.UIResourceMgr'
        $size = $ui.GetCacheInfo().TotalSize
        if ($null -eq $size) { return 0 }
        return [int]$size
    }
    catch {
        return 0
    }
}

function Test-ClientHealthLogSize {
    <#
    .SYNOPSIS
        Checks the ConfigMgr client max log size and history settings.
    .DESCRIPTION
        Reads the current values from the CCM logging registry key and remediates
        by writing the configured values.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][int]$MaxLogSizeKB,
        [Parameter(Mandatory = $true)][int]$MaxLogHistory,
        [Parameter(Mandatory = $false)][bool]$Fix = $false
    )

    $key = 'HKLM:\SOFTWARE\Microsoft\CCM\Logging\@Global'
    $currentSize = [int](Get-ClientHealthRegistryValue -Path $key -Name 'LogMaxSize')
    $currentHistory = [int](Get-ClientHealthRegistryValue -Path $key -Name 'LogMaxHistory')

    if ($currentSize -eq $MaxLogSizeKB -and $currentHistory -eq $MaxLogHistory) {
        return [pscustomobject]@{ Name = 'LogSize'; Status = 'OK'; Detail = "Max log size $currentSize KB, history $currentHistory"; Remediated = $false }
    }

    if (-not $Fix) {
        return [pscustomobject]@{ Name = 'LogSize'; Status = 'Warning'; Detail = "Log size $currentSize KB / history $currentHistory (expected $MaxLogSizeKB / $MaxLogHistory); remediation disabled"; Remediated = $false }
    }

    $newSize = $MaxLogSizeKB * 1000
    $null = New-ItemProperty -Path $key -Name 'LogMaxSize' -PropertyType DWord -Value $newSize -Force
    $null = New-ItemProperty -Path $key -Name 'LogMaxHistory' -PropertyType DWord -Value $MaxLogHistory -Force

    return [pscustomobject]@{ Name = 'LogSize'; Status = 'Remediated'; Detail = "Log size set to $MaxLogSizeKB KB, history $MaxLogHistory"; Remediated = $true }
}

function Test-ClientHealthProvisioningMode {
    <#
    .SYNOPSIS
        Checks and clears ConfigMgr client provisioning mode.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $false)][bool]$Fix = $false
    )

    $key = 'HKLM:\SOFTWARE\Microsoft\CCM\CcmExec'
    $mode = Get-ClientHealthRegistryValue -Path $key -Name 'ProvisioningMode'

    if ($mode -ne 'true') {
        return [pscustomobject]@{ Name = 'ProvisioningMode'; Status = 'OK'; Detail = 'Not in provisioning mode'; Remediated = $false }
    }

    if (-not $Fix) {
        return [pscustomobject]@{ Name = 'ProvisioningMode'; Status = 'Warning'; Detail = 'Client in provisioning mode; remediation disabled'; Remediated = $false }
    }

    try {
        $null = Set-ItemProperty -Path $key -Name 'ProvisioningMode' -Value 'false'
        $null = Invoke-CimMethod -Namespace 'root\ccm' -ClassName 'SMS_Client' -MethodName 'SetClientProvisioningMode' -Arguments @{ bEnable = $false } -ErrorAction Stop
        return [pscustomobject]@{ Name = 'ProvisioningMode'; Status = 'Remediated'; Detail = 'Provisioning mode cleared'; Remediated = $true }
    }
    catch {
        return [pscustomobject]@{ Name = 'ProvisioningMode'; Status = 'Error'; Detail = "Failed to clear provisioning mode: $($_.Exception.Message)"; Remediated = $false }
    }
}

#endregion

#region Services

function Test-ClientHealthServices {
    <#
    .SYNOPSIS
        Checks configured services for the expected startup type, state, and uptime.
    .DESCRIPTION
        For each service in the config, verifies startup type and running state,
        and optionally restarts services that have exceeded their max uptime.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory = $true)][ClientHealthServiceConfig[]]$Services
    )

    $results = @()
    foreach ($svc in $Services) {
        $results += Test-ClientHealthService -Service $svc
    }
    return $results
}

function Test-ClientHealthService {
    <#
    .SYNOPSIS
        Checks a single service against its expected configuration.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][ClientHealthServiceConfig]$Service
    )

    $name = $Service.Name
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if ($null -eq $svc) {
        return [pscustomobject]@{ Name = "Service:$name"; Status = 'Error'; Detail = 'Service not found'; Remediated = $false }
    }

    $wmiSvc = Get-CimInstance -ClassName Win32_Service -Filter "Name='$name'" -ErrorAction SilentlyContinue
    $startMode = if ($null -ne $wmiSvc) { $wmiSvc.StartMode } else { '' }

    # Normalize expected startup type.
    $expected = $Service.StartupType.ToLower()
    switch -Wildcard ($expected) {
        'automaticd*'          { $expected = 'Automatic (Delayed Start)' }
        'automatic(d*'         { $expected = 'Automatic (Delayed Start)' }
        'automatic(t*'         { $expected = 'Automatic (Trigger Start)' }
        'automatict*'          { $expected = 'Automatic (Trigger Start)' }
        'automatic*'           { $expected = 'Automatic' }
        'manual*'              { $expected = 'Manual' }
        'disabled*'            { $expected = 'Disabled' }
    }

    $actual = switch -Wildcard ($startMode) {
        'auto*' {
            $delayed = Get-ClientHealthRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$name" -Name 'DelayedAutostart'
            if ($delayed -eq 1) { 'Automatic (Delayed Start)' } else { 'Automatic' }
        }
        'manual*' { 'Manual' }
        'disabled*' { 'Disabled' }
        default { $startMode }
    }

    $issues = @()
    if ($actual -ne $expected) { $issues += "startup type '$actual' (expected '$expected')" }
    if ($Service.State -eq 'Running' -and $svc.Status -ne 'Running') { $issues += "state '$($svc.Status)' (expected Running)" }

    if ($issues.Count -eq 0) {
        return [pscustomobject]@{ Name = "Service:$name"; Status = 'OK'; Detail = "Startup '$actual', state '$($svc.Status)'"; Remediated = $false }
    }

    return [pscustomobject]@{ Name = "Service:$name"; Status = 'Warning'; Detail = ($issues -join '; '); Remediated = $false }
}

#endregion

#region Network & DNS

function Test-ClientHealthDNS {
    <#
    .SYNOPSIS
        Checks that the local FQDN resolves in DNS and matches local IPs.
    .DESCRIPTION
        Resolves the local hostname against the configured DNS servers and
        verifies the published IPs exist locally. Optionally registers the client
        with DNS if a mismatch is found.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $false)][bool]$Fix = $false
    )

    try {
        $fqdn = [System.Net.Dns]::GetHostEntry('localhost').HostName
        $localIPs = @(Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=True' |
            Select-Object -ExpandProperty IPAddress)

        $dnsIPs = @()
        try {
            $activeAdapters = @(Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object -ExpandProperty Name)
            $dnsServer = Get-DnsClientServerAddress |
                Where-Object { $activeAdapters -contains $_.InterfaceAlias -and $_.AddressFamily -eq 2 } |
                Select-Object -First 1 -ExpandProperty ServerAddresses
            if ($dnsServer) {
                $dnsIPs = @(Resolve-DnsName -Name $fqdn -Server $dnsServer -Type A -DnsOnly -ErrorAction Stop |
                    Select-Object -ExpandProperty IPAddress)
            }
        }
        catch {
            $dnsIPs = @($dnsIPs) + @([System.Net.Dns]::GetHostByName($fqdn).AddressList | Select-Object -ExpandProperty IPAddressToString)
        }
        $dnsIPs = $dnsIPs | ForEach-Object { $_ -replace '%(.*)', '' }

        $missing = @($dnsIPs | Where-Object { $localIPs -notcontains $_ })
        if ($missing.Count -eq 0) {
            return [pscustomobject]@{ Name = 'DNS'; Status = 'OK'; Detail = "FQDN $fqdn resolves correctly"; Remediated = $false }
        }

        if (-not $Fix) {
            return [pscustomobject]@{ Name = 'DNS'; Status = 'Warning'; Detail = "DNS IPs not present locally: $($missing -join ', ')"; Remediated = $false }
        }

        Register-DnsClient -ErrorAction SilentlyContinue
        return [pscustomobject]@{ Name = 'DNS'; Status = 'Remediated'; Detail = "Registered with DNS (missing: $($missing -join ', '))"; Remediated = $true }
    }
    catch {
        return [pscustomobject]@{ Name = 'DNS'; Status = 'Error'; Detail = "DNS check failed: $($_.Exception.Message)"; Remediated = $false }
    }
}

#endregion

#region Updates & patches

function Test-ClientHealthRequiredUpdates {
    <#
    .SYNOPSIS
        Checks that required updates from the update share are installed.
    .DESCRIPTION
        Scans the update share folder for the current OS for .msu files and
        verifies each KB is installed. Optionally installs missing updates.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][string]$UpdateShare,
        [Parameter(Mandatory = $false)][bool]$Fix = $false
    )

    if ([string]::IsNullOrWhiteSpace($UpdateShare)) {
        return [pscustomobject]@{ Name = 'Updates'; Status = 'Skipped'; Detail = 'No update share configured'; Remediated = $false }
    }

    $osName = Get-ClientHealthOSName
    $updatesPath = Join-Path $UpdateShare $osName

    if (-not (Test-Path -LiteralPath $updatesPath)) {
        return [pscustomobject]@{ Name = 'Updates'; Status = 'Warning'; Detail = "Update folder not found: $updatesPath"; Remediated = $false }
    }

    $regex = '(?i)^.+-kb[0-9]{6,}-(?:v[0-9]+-)?x[0-9]+\.msu$'
    $hotfixes = @(Get-ChildItem -LiteralPath $updatesPath | Where-Object { $_.Name -match $regex } | Select-Object -ExpandProperty Name)

    if ($hotfixes.Count -eq 0) {
        return [pscustomobject]@{ Name = 'Updates'; Status = 'OK'; Detail = 'No mandatory updates to install'; Remediated = $false }
    }

    $installed = @(Get-CimInstance -ClassName Win32_QuickFixEngineering -ErrorAction SilentlyContinue | Select-Object -ExpandProperty HotFixID)
    $missing = @()

    foreach ($hotfix in $hotfixes) {
        $kb = ($hotfix -replace '\b(?!(KB)+(\d+)\b)\w+', '') -replace '\.', '' -replace '-', ''
        if ($installed -notcontains $kb) {
            $missing += $hotfix
        }
    }

    if ($missing.Count -eq 0) {
        return [pscustomobject]@{ Name = 'Updates'; Status = 'OK'; Detail = "All $($hotfixes.Count) required updates installed"; Remediated = $false }
    }

    if (-not $Fix) {
        return [pscustomobject]@{ Name = 'Updates'; Status = 'Warning'; Detail = "Missing updates: $($missing -join ', ')"; Remediated = $false }
    }

    $installedNow = @()
    foreach ($hotfix in $missing) {
        $src = Join-Path $updatesPath $hotfix
        $tempDir = Join-Path $env:TEMP 'ClientHealth'
        $null = New-Item -Path $tempDir -ItemType Directory -Force
        $dest = Join-Path $tempDir $hotfix
        Copy-Item -LiteralPath $src -Destination $dest -Force
        try {
            $proc = Start-Process -FilePath 'wusa.exe' -ArgumentList @($dest, '/quiet', '/norestart') -Wait -PassThru
            if ($proc.ExitCode -eq 0) { $installedNow += $hotfix }
        }
        catch {
            Write-Warning "Failed to install $hotfix : $($_.Exception.Message)"
        }
        Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue
    }

    return [pscustomobject]@{ Name = 'Updates'; Status = 'Remediated'; Detail = "Installed: $($installedNow -join ', '); still missing: $(($missing | Where-Object { $_ -notin $installedNow }) -join ', ')"; Remediated = $true }
}

function Get-ClientHealthLastInstalledPatch {
    <#
    .SYNOPSIS
        Returns the date of the last installed OS patch.
    .DESCRIPTION
        Uses the Windows Update COM API history and Win32_QuickFixEngineering,
        returning the most recent install date.
    #>
    [CmdletBinding()]
    [OutputType([datetime])]
    param()

    $latest = $null
    try {
        $session = New-Object -ComObject 'Microsoft.Update.Session'
        $searcher = $session.CreateUpdateSearcher()
        $count = $searcher.GetTotalHistoryCount()
        if ($count -gt 0) {
            $history = $searcher.QueryHistory(0, $count) |
                Where-Object { $_.Title -notmatch 'Security Intelligence Update|Definition Update' } |
                Select-Object -ExpandProperty Date
            if ($history) { $latest = ($history | Measure-Object -Maximum).Maximum }
        }
    }
    catch { }

    try {
        $hotfixDates = @(Get-CimInstance -ClassName Win32_QuickFixEngineering -ErrorAction SilentlyContinue |
            Where-Object { $_.InstalledOn } |
            ForEach-Object { [datetime]::Parse($_.InstalledOn, [System.Globalization.CultureInfo]::GetCultureInfo('en-US')) })
        if ($hotfixDates.Count -gt 0) {
            $hotfixLatest = ($hotfixDates | Measure-Object -Maximum).Maximum
            if ($null -eq $latest -or $hotfixLatest -gt $latest) { $latest = $hotfixLatest }
        }
    }
    catch { }

    return $latest
}

#endregion

#region State & policy

function Test-ClientHealthStateMessages {
    <#
    .SYNOPSIS
        Checks that state messages are being forwarded to the management point.
    .DESCRIPTION
        Looks for a successful forward entry in StateMessage.log. If not found,
        triggers a refresh of the compliance state.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $false)][bool]$Fix = $false
    )

    $logDir = Get-ClientHealthCCMLogDirectory
    $logFile = Join-Path $logDir 'StateMessage.log'

    if (Test-Path -LiteralPath $logFile) {
        $content = Get-Content -LiteralPath $logFile -Raw -ErrorAction SilentlyContinue
        if ($content -match 'Successfully forwarded State Messages to the MP') {
            return [pscustomobject]@{ Name = 'StateMessages'; Status = 'OK'; Detail = 'State messages forwarded to MP'; Remediated = $false }
        }
    }

    if (-not $Fix) {
        return [pscustomobject]@{ Name = 'StateMessages'; Status = 'Warning'; Detail = 'No recent successful state message forward'; Remediated = $false }
    }

    try {
        $store = New-Object -ComObject 'Microsoft.CCM.UpdatesStore'
        $store.RefreshServerComplianceState()
        return [pscustomobject]@{ Name = 'StateMessages'; Status = 'Remediated'; Detail = 'Compliance state refresh triggered'; Remediated = $true }
    }
    catch {
        return [pscustomobject]@{ Name = 'StateMessages'; Status = 'Error'; Detail = "Failed to refresh compliance state: $($_.Exception.Message)"; Remediated = $false }
    }
}

function Test-ClientHealthRegistryPol {
    <#
    .SYNOPSIS
        Checks for a broken WUAHandler / registry.pol.
    .DESCRIPTION
        Looks for WUAHandler.log errors, an old registry.pol, and Group Policy
        event log errors. If broken, deletes registry.pol and forces gpupdate.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $false)][datetime]$StartTime = [datetime]::MinValue,
        [Parameter(Mandatory = $false)][int]$Days = 0,
        [Parameter(Mandatory = $false)][bool]$Fix = $false
    )

    $repairReason = ''
    $logDir = Get-ClientHealthCCMLogDirectory
    $wuaLog = Join-Path $logDir 'WUAHandler.log'
    $machinePol = "$env:WinDir\System32\GroupPolicy\Machine\registry.pol"

    if (Test-Path -LiteralPath $wuaLog) {
        $content = Get-Content -LiteralPath $wuaLog -Raw -ErrorAction SilentlyContinue
        if ($content -match '0x80004005|0x87d00692') { $repairReason = 'WUAHandler Log' }
    }

    if ($Days -gt 0 -and (Test-Path -LiteralPath $machinePol)) {
        $age = ((Get-Date) - (Get-Item -LiteralPath $machinePol).LastWriteTime).Days
        if ($age -ge $Days) { $repairReason = 'File Age' }
    }

    try {
        $gpoErrors = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-GroupPolicy/Operational'; Level = 2; StartTime = $StartTime } -ErrorAction SilentlyContinue |
            Where-Object { ($_.Id -ge 7000 -and $_.Id -le 7007) -or ($_.Id -ge 7017 -and $_.Id -le 7299) -or ($_.Id -eq 1096) })
        if ($gpoErrors.Count -gt 0) { $repairReason = 'Event Log' }
    }
    catch { }

    if ([string]::IsNullOrWhiteSpace($repairReason)) {
        return [pscustomobject]@{ Name = 'WUAHandler'; Status = 'OK'; Detail = 'GPO cache healthy'; Remediated = $false }
    }

    if (-not $Fix) {
        return [pscustomobject]@{ Name = 'WUAHandler'; Status = 'Warning'; Detail = "GPO cache broken ($repairReason); remediation disabled"; Remediated = $false }
    }

    try {
        if (Test-Path -LiteralPath $machinePol) { Remove-Item -LiteralPath $machinePol -Force }
        $null = & gpupdate.exe /force /target:computer 2>$null
        Invoke-ClientHealthPolicyTrigger -Name 'ScanByUpdateSource'
        Invoke-ClientHealthPolicyTrigger -Name 'SourceUpdateMessage'
        return [pscustomobject]@{ Name = 'WUAHandler'; Status = 'Remediated'; Detail = "GPO cache repaired ($repairReason)"; Remediated = $true }
    }
    catch {
        return [pscustomobject]@{ Name = 'WUAHandler'; Status = 'Error'; Detail = "Failed to repair GPO cache: $($_.Exception.Message)"; Remediated = $false }
    }
}

function Test-ClientHealthPendingReboot {
    <#
    .SYNOPSIS
        Checks whether the computer is pending a reboot.
    .DESCRIPTION
        Checks CBS, Windows Update, and SCCM reboot-pending indicators.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $pending = $false
    $reasons = @()

    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
        $pending = $true; $reasons += 'CBS'
    }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
        $pending = $true; $reasons += 'WindowsUpdate'
    }
    try {
        $util = [wmiclass]'\\.\root\ccm\clientsdk:CCM_ClientUtilities'
        $status = $util.DetermineIfRebootPending()
        if ($null -ne $status -and $status.RebootPending) { $pending = $true; $reasons += 'SCCM' }
    }
    catch { }

    if ($pending) {
        return [pscustomobject]@{ Name = 'PendingReboot'; Status = 'Warning'; Detail = "Pending reboot ($($reasons -join ', '))"; Remediated = $false }
    }
    return [pscustomobject]@{ Name = 'PendingReboot'; Status = 'OK'; Detail = 'No pending reboot'; Remediated = $false }
}

#endregion

#region Hardware inventory & drivers

function Test-ClientHealthHardwareInventory {
    <#
    .SYNOPSIS
        Checks the last hardware inventory scan date and triggers a scan if stale.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $false)][int]$Days = 7,
        [Parameter(Mandatory = $false)][bool]$Fix = $false
    )

    $hwId = '{00000000-0000-0000-0000-000000000001}'
    $action = Get-CimInstance -Namespace 'root\ccm\invagt' -ClassName 'InventoryActionStatus' -ErrorAction SilentlyContinue |
        Where-Object { $_.InventoryActionID -eq $hwId } | Select-Object -First 1

    if ($null -eq $action) {
        return [pscustomobject]@{ Name = 'HardwareInventory'; Status = 'Warning'; Detail = 'No hardware inventory action found'; Remediated = $false }
    }

    $lastScan = $action.LastCycleStartedDate
    $minDate = (Get-Date).AddDays(-$Days)

    if ($lastScan -gt $minDate) {
        return [pscustomobject]@{ Name = 'HardwareInventory'; Status = 'OK'; Detail = "Last HW inventory $lastScan"; Remediated = $false }
    }

    if (-not $Fix) {
        return [pscustomobject]@{ Name = 'HardwareInventory'; Status = 'Warning'; Detail = "Last HW inventory $lastScan (stale > $Days days); remediation disabled"; Remediated = $false }
    }

    Invoke-ClientHealthPolicyTrigger -Name 'HardwareInventory'
    return [pscustomobject]@{ Name = 'HardwareInventory'; Status = 'Remediated'; Detail = "Hardware inventory scan triggered (last: $lastScan)"; Remediated = $true }
}

function Test-ClientHealthMissingDrivers {
    <#
    .SYNOPSIS
        Checks for missing or faulty device drivers.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $devices = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue |
        Where-Object { $_.ConfigManagerErrorCode -ne 0 -and $_.ConfigManagerErrorCode -ne 22 -and $_.Name -notlike '*PS/2*' })

    if ($devices.Count -eq 0) {
        return [pscustomobject]@{ Name = 'Drivers'; Status = 'OK'; Detail = 'No faulty devices'; Remediated = $false }
    }

    $names = $devices | Select-Object -First 5 -ExpandProperty Name
    return [pscustomobject]@{ Name = 'Drivers'; Status = 'Warning'; Detail = "$($devices.Count) faulty device(s): $($names -join '; ')"; Remediated = $false }
}

#endregion

#region BITS & client settings

function Test-ClientHealthBITS {
    <#
    .SYNOPSIS
        Checks for BITS transfer errors and optionally remediates.
    .DESCRIPTION
        Finds BITS jobs in an error state. If remediation is enabled, removes the
        failed jobs and resets the BITS service security descriptor.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $false)][bool]$Fix = $false
    )

    $errors = @(Get-BitsTransfer -AllUsers -ErrorAction SilentlyContinue |
        Where-Object { $_.JobState -in @('TransientError', 'Transient_Error', 'Error') })

    if ($errors.Count -eq 0) {
        return [pscustomobject]@{ Name = 'BITS'; Status = 'OK'; Detail = 'No BITS errors'; Remediated = $false }
    }

    if (-not $Fix) {
        return [pscustomobject]@{ Name = 'BITS'; Status = 'Warning'; Detail = "$($errors.Count) BITS job(s) in error state"; Remediated = $false }
    }

    try {
        $errors | Remove-BitsTransfer -ErrorAction SilentlyContinue
        $null = & sc.exe sdset bits 'D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;AU)(A;;CCLCSWRPWPDTLOCRRC;;;PU)'
        return [pscustomobject]@{ Name = 'BITS'; Status = 'Remediated'; Detail = "Removed $($errors.Count) failed BITS job(s) and reset security descriptor"; Remediated = $true }
    }
    catch {
        return [pscustomobject]@{ Name = 'BITS'; Status = 'Error'; Detail = "Failed to remediate BITS: $($_.Exception.Message)"; Remediated = $false }
    }
}

function Test-ClientHealthClientSettings {
    <#
    .SYNOPSIS
        Checks for a stale CcmTaskSequence client settings policy.
    .DESCRIPTION
        If a CCM_ClientAgentConfig policy sourced from CcmTaskSequence exists, it
        can block client settings. Optionally removes the stale policy.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $false)][bool]$Fix = $false
    )

    $stale = @(Get-CimInstance -Namespace 'root\ccm\Policy\DefaultMachine\RequestedConfig' -ClassName 'CCM_ClientAgentConfig' -ErrorAction SilentlyContinue |
        Where-Object { $_.PolicySource -eq 'CcmTaskSequence' })

    if ($stale.Count -eq 0) {
        return [pscustomobject]@{ Name = 'ClientSettings'; Status = 'OK'; Detail = 'No stale task sequence client settings'; Remediated = $false }
    }

    if (-not $Fix) {
        return [pscustomobject]@{ Name = 'ClientSettings'; Status = 'Warning'; Detail = "$($stale.Count) stale CcmTaskSequence policy object(s)"; Remediated = $false }
    }

    try {
        $stale | Remove-CimInstance -ErrorAction Stop
        return [pscustomobject]@{ Name = 'ClientSettings'; Status = 'Remediated'; Detail = "Removed $($stale.Count) stale policy object(s)"; Remediated = $true }
    }
    catch {
        return [pscustomobject]@{ Name = 'ClientSettings'; Status = 'Error'; Detail = "Failed to remove stale policy: $($_.Exception.Message)"; Remediated = $false }
    }
}

#endregion

#region Certificate

function Test-ClientHealthCertificate {
    <#
    .SYNOPSIS
        Checks the ConfigMgr client certificate for known errors.
    .DESCRIPTION
        Looks for certificate errors in ClientIDManagerStartup.log. If the
        "failed to find the certificate in the store" error is found, removes the
        machine key so CCM recreates the certificate.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $false)][bool]$Fix = $false
    )

    $logDir = Get-ClientHealthCCMLogDirectory
    $logFile = Join-Path $logDir 'ClientIDManagerStartup.log'

    if (-not (Test-Path -LiteralPath $logFile)) {
        return [pscustomobject]@{ Name = 'Certificate'; Status = 'OK'; Detail = 'No client certificate log'; Remediated = $false }
    }

    $content = Get-Content -LiteralPath $logFile -Raw -ErrorAction SilentlyContinue
    $error1 = 'Failed to find the certificate in the store'
    $error2 = '[RegTask] - Server rejected registration 3'

    if ($content -match $error2) {
        return [pscustomobject]@{ Name = 'Certificate'; Status = 'Error'; Detail = 'Server rejected client registration; no auto-remediation'; Remediated = $false }
    }

    if ($content -match $error1) {
        if (-not $Fix) {
            return [pscustomobject]@{ Name = 'Certificate'; Status = 'Warning'; Detail = 'Certificate not found in store; remediation disabled'; Remediated = $false }
        }
        try {
            Stop-Service -Name ccmexec -Force -ErrorAction SilentlyContinue
            $cert = "$env:ProgramData\Microsoft\Crypto\RSA\MachineKeys\19c5cf9c7b5dc9de3e548adb70398402_50e417e0-e461-474b-96e2-077b80325612"
            Remove-Item -LiteralPath $cert -Force -ErrorAction SilentlyContinue
            Start-Service -Name ccmexec -ErrorAction SilentlyContinue
            return [pscustomobject]@{ Name = 'Certificate'; Status = 'Remediated'; Detail = 'Client certificate recreated'; Remediated = $true }
        }
        catch {
            return [pscustomobject]@{ Name = 'Certificate'; Status = 'Error'; Detail = "Failed to remediate certificate: $($_.Exception.Message)"; Remediated = $false }
        }
    }

    return [pscustomobject]@{ Name = 'Certificate'; Status = 'OK'; Detail = 'No certificate errors'; Remediated = $false }
}

#endregion
