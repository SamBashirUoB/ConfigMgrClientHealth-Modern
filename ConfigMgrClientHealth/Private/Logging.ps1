# Private\Logging.ps1
# CMTrace-compatible structured logging.
#
# The original tool hand-built CMTrace log lines with string concatenation.
# This version uses a single Write-ClientHealthLog function that emits
# CMTrace-compatible entries (so logs still open in CMTrace / OneTrace) while
# keeping the code clean and testable.

#region Logging

function Write-ClientHealthLog {
    <#
    .SYNOPSIS
        Writes a CMTrace-compatible log entry.
    .DESCRIPTION
        Emits a log line in the CMTrace XML format to the specified log file.
        Severity: 1 = Information, 2 = Warning, 3 = Error.
    .PARAMETER Message
        The log message text.
    .PARAMETER LogFile
        Full path to the log file to append to.
    .PARAMETER Severity
        Log severity (1=Information, 2=Warning, 3=Error).
    .PARAMETER Component
        Component name recorded in the log entry.
    .EXAMPLE
        Write-ClientHealthLog -Message 'Check started' -LogFile C:\ClientHealth\ClientHealth.log
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyString()]
        [string]$Message,

        [Parameter(Mandatory = $true)]
        [string]$LogFile,

        [Parameter(Mandatory = $false)]
        [ValidateSet(1, 2, 3, 'Information', 'Warning', 'Error')]
        $Severity = 1,

        [Parameter(Mandatory = $false)]
        [string]$Component = 'ConfigMgrClientHealth'
    )

    switch ($Severity) {
        'Information' { $Severity = 1 }
        'Warning'     { $Severity = 2 }
        'Error'       { $Severity = 3 }
    }

    $dir = Split-Path -Parent $LogFile
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        $null = New-Item -Path $dir -ItemType Directory -Force
    }

    $now = Get-Date
    $time = $now.ToString('HH:mm:ss.fff') + '+000'
    $date = $now.ToString('MM-dd-yyyy')
    $thread = $PID

    $logBlock = '<![LOG[{0}]LOG]!><time="{1}" date="{2}" component="{3}" context="" type="{4}" thread="{5}" file="">' -f `
        $Message, $time, $date, $Component, $Severity, $thread

    Add-Content -LiteralPath $LogFile -Value $logBlock -Encoding UTF8
}

function Write-ClientHealthLogObject {
    <#
    .SYNOPSIS
        Writes a full health-check result object to a CMTrace-compatible log file.
    .DESCRIPTION
        Serializes the health check log object (all check results) into a single
        CMTrace log entry for post-run review.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Log,
        [Parameter(Mandatory = $true)][string]$LogFile
    )

    $props = $Log.PSObject.Properties | Where-Object { $null -ne $_.Value } |
        ForEach-Object { '{0}: {1}' -f $_.Name, $_.Value }

    $text = "<--- ConfigMgr Client Health Check --->`n" + ($props -join "`n")
    Write-ClientHealthLog -Message $text -LogFile $LogFile -Severity 1
}

function Test-ClientHealthLogHistory {
    <#
    .SYNOPSIS
        Trims a log file when it exceeds the configured max history.
    .DESCRIPTION
        Counts the number of "<--- ConfigMgr Client Health Check --->" markers in
        the log file and deletes it if it exceeds MaxHistory runs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$LogFile,
        [Parameter(Mandatory = $false)][int]$MaxHistory = 10
    )

    if (-not (Test-Path -LiteralPath $LogFile)) { return }

    $marker = '<--- ConfigMgr Client Health Check --->'
    $count = (Select-String -LiteralPath $LogFile -Pattern $marker -SimpleMatch -ErrorAction SilentlyContinue).Count
    if ($count -ge $MaxHistory) {
        Remove-Item -LiteralPath $LogFile -Force
    }
}

#endregion
