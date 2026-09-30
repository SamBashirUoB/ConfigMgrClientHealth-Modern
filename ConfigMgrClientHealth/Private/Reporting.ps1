# Private\Reporting.ps1
# Reporting: SQL database and REST webservice submission of health results.
#
# The original tool wrote results to a SQL database (dbo.Clients) and a REST
# webservice (PUT/POST /Clients). This version keeps both, but uses parameterized
# SQL (no string-concatenated queries) and Invoke-RestMethod.

#region SQL reporting

function Send-ClientHealthReportToSql {
    <#
    .SYNOPSIS
        Writes a health report to the ClientHealth SQL database.
    .DESCRIPTION
        Uses a parameterized INSERT into the dbo.Clients table. The table is
        created if it does not exist. Returns $true on success.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]$Log,
        [Parameter(Mandatory = $true)][string]$Server,
        [Parameter(Mandatory = $false)][string]$Database = 'ClientHealth'
    )

    if ([string]::IsNullOrWhiteSpace($Server)) {
        Write-Warning 'SQL reporting skipped: no server configured'
        return $false
    }

    $conn = $null
    try {
        $conn = New-Object System.Data.SqlClient.SqlConnection
        $conn.ConnectionString = "Server=$Server;Database=$Database;Integrated Security=SSPI;"
        $conn.Open()

        $createTable = @'
IF OBJECT_ID('dbo.Clients', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Clients (
        Hostname NVARCHAR(255) NOT NULL,
        Operatingsystem NVARCHAR(255) NULL,
        Architecture NVARCHAR(50) NULL,
        Build NVARCHAR(50) NULL,
        Manufacturer NVARCHAR(255) NULL,
        Model NVARCHAR(255) NULL,
        InstallDate DATETIME NULL,
        OSUpdates NVARCHAR(MAX) NULL,
        LastLoggedOnUser NVARCHAR(255) NULL,
        ClientVersion NVARCHAR(50) NULL,
        PSVersion NVARCHAR(50) NULL,
        PSBuild NVARCHAR(50) NULL,
        Sitecode NVARCHAR(50) NULL,
        Domain NVARCHAR(255) NULL,
        MaxLogSize NVARCHAR(50) NULL,
        MaxLogHistory NVARCHAR(50) NULL,
        CacheSize NVARCHAR(50) NULL,
        ClientCertificate NVARCHAR(50) NULL,
        ProvisioningMode NVARCHAR(50) NULL,
        DNS NVARCHAR(50) NULL,
        Drivers NVARCHAR(50) NULL,
        Updates NVARCHAR(50) NULL,
        PendingReboot NVARCHAR(50) NULL,
        LastBootTime DATETIME NULL,
        OSDiskFreeSpace NVARCHAR(50) NULL,
        Services NVARCHAR(MAX) NULL,
        AdminShare NVARCHAR(50) NULL,
        StateMessages NVARCHAR(50) NULL,
        WUAHandler NVARCHAR(50) NULL,
        WMI NVARCHAR(50) NULL,
        RefreshComplianceState NVARCHAR(50) NULL,
        HWInventory NVARCHAR(50) NULL,
        SWMetering NVARCHAR(50) NULL,
        ClientSettings NVARCHAR(50) NULL,
        BITS NVARCHAR(50) NULL,
        PatchLevel NVARCHAR(50) NULL,
        ClientInstalledReason NVARCHAR(255) NULL,
        RebootApp NVARCHAR(50) NULL,
        Version NVARCHAR(50) NULL,
        Timestamp DATETIME NULL,
        ClientInstalled NVARCHAR(50) NULL
    );
END
'@
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $createTable
        $null = $cmd.ExecuteNonQuery()

        $insert = @'
INSERT INTO dbo.Clients (
    Hostname, Operatingsystem, Architecture, Build, Manufacturer, Model,
    InstallDate, OSUpdates, LastLoggedOnUser, ClientVersion, PSVersion, PSBuild,
    Sitecode, Domain, MaxLogSize, MaxLogHistory, CacheSize, ClientCertificate,
    ProvisioningMode, DNS, Drivers, Updates, PendingReboot, LastBootTime,
    OSDiskFreeSpace, Services, AdminShare, StateMessages, WUAHandler, WMI,
    RefreshComplianceState, HWInventory, SWMetering, ClientSettings, BITS,
    PatchLevel, ClientInstalledReason, RebootApp, Version, Timestamp, ClientInstalled
) VALUES (
    @Hostname, @Operatingsystem, @Architecture, @Build, @Manufacturer, @Model,
    @InstallDate, @OSUpdates, @LastLoggedOnUser, @ClientVersion, @PSVersion, @PSBuild,
    @Sitecode, @Domain, @MaxLogSize, @MaxLogHistory, @CacheSize, @ClientCertificate,
    @ProvisioningMode, @DNS, @Drivers, @Updates, @PendingReboot, @LastBootTime,
    @OSDiskFreeSpace, @Services, @AdminShare, @StateMessages, @WUAHandler, @WMI,
    @RefreshComplianceState, @HWInventory, @SWMetering, @ClientSettings, @BITS,
    @PatchLevel, @ClientInstalledReason, @RebootApp, @Version, @Timestamp, @ClientInstalled
)
'@
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $insert

        $null = $cmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter('@Hostname', [string]$Log.Hostname)))
        $null = $cmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter('@Operatingsystem', [string]$Log.Operatingsystem)))
        $null = $cmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter('@Architecture', [string]$Log.Architecture)))
        $null = $cmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter('@Build', [string]$Log.Build)))
        $null = $cmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter('@Manufacturer', [string]$Log.Manufacturer)))
        $null = $cmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter('@Model', [string]$Log.Model)))
        $null = $cmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter('@InstallDate', [datetime]$Log.InstallDate)))
        $null = $cmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter('@OSUpdates', [string]$Log.OSUpdates)))
        $null = $cmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter('@LastLoggedOnUser', [string]$Log.LastLoggedOnUser)))
        $null = $cmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter('@ClientVersion', [string]$Log.ClientVersion)))
        $null = $cmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter('@PSVersion', [string]$Log.PSVersion)))
        $null = $cmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter('@PSBuild', [string]$Log.PSBuild)))
        $null = $cmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter('@Sitecode', [string]$Log.Sitecode)))
        $null = $cmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter('@Domain', [string]$Log.Domain)))
        $null = $cmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter('@MaxLogSize', [string]$Log.MaxLogSize)))
        $null = $cmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter('@MaxLogHistory', [string]$Log.MaxLogHistory)))
        $null = $cmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter('@CacheSize', [string]$Log.CacheSize)))
        $null = $cmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter('@ClientCertificate', [string]$Log.ClientCertificate)))
        $null = $cmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter('@ProvisioningMode', [string]$Log.ProvisioningMode)))
        $null = $cmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter('@DNS', [string]$Log.DNS)))
        $null = $cmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter('@Drivers', [string]$Log.Drivers)))
        $null = $cmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter('@Updates', [string]$Log.Updates)))
        $null = $cmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter('@PendingReboot', [string]$Log.PendingReboot)))
        $null = $cmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter('@LastBootTime', [datetime]$Log.LastBootTime)))
        $null = $cmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter('@OSDiskFreeSpace', [string]$Log.OSDiskFreeSpace)))
        $null = $cmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter('@Services', [string]$Log.Services)))
        $null = $cmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter('@AdminShare', [string]$Log.AdminShare)))
        $null = $cmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter('@StateMessages', [string]$Log.StateMessages)))
        $null = $cmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter('@WUAHandler', [string]$Log.WUAHandler)))
        $null = $cmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter('@WMI', [string]$Log.WMI)))
        $null = $cmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter('@RefreshComplianceState', [string]$Log.RefreshComplianceState)))
        $null = $cmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter('@HWInventory', [string]$Log.HWInventory)))
        $null = $cmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter('@SWMetering', [string]$Log.SWMetering)))
        $null = $cmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter('@ClientSettings', [string]$Log.ClientSettings)))
        $null = $cmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter('@BITS', [string]$Log.BITS)))
        $null = $cmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter('@PatchLevel', [string]$Log.PatchLevel)))
        $null = $cmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter('@ClientInstalledReason', [string]$Log.ClientInstalledReason)))
        $null = $cmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter('@RebootApp', [string]$Log.RebootApp)))
        $null = $cmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter('@Version', [string]$Log.Version)))
        $null = $cmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter('@Timestamp', [datetime]$Log.Timestamp)))
        $null = $cmd.Parameters.Add((New-Object System.Data.SqlClient.SqlParameter('@ClientInstalled', [string]$Log.ClientInstalled)))

        $null = $cmd.ExecuteNonQuery()
        return $true
    }
    catch {
        Write-Warning "SQL reporting failed: $($_.Exception.Message)"
        return $false
    }
    finally {
        if ($null -ne $conn) { $conn.Dispose() }
    }
}

#endregion

#region Webservice reporting

function Send-ClientHealthReportToWebservice {
    <#
    .SYNOPSIS
        Submits a health report to the REST webservice.
    .DESCRIPTION
        PUTs the report to the /Clients endpoint. Returns $true on success.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]$Log,
        [Parameter(Mandatory = $true)][string]$Uri
    )

    if ([string]::IsNullOrWhiteSpace($Uri)) {
        Write-Warning 'Webservice reporting skipped: no URI configured'
        return $false
    }

    try {
        $body = $Log | ConvertTo-Json -Depth 3
        $null = Invoke-RestMethod -Method Put -Uri $Uri -Body $body -ContentType 'application/json' -ErrorAction Stop
        return $true
    }
    catch {
        Write-Warning "Webservice reporting failed: $($_.Exception.Message)"
        return $false
    }
}

#endregion
