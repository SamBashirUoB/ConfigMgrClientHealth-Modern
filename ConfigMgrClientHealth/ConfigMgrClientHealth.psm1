# ConfigMgrClientHealth.psm1
# Modernized ConfigMgr (SCCM) Client Health module.
#
# This module is a modern rewrite of the classic "ConfigMgr Client Health"
# tool by Anders Rodland (https://github.com/AndersRodland/ConfigMgrClientHealth).
# It keeps the same feature set (health checks + auto-remediation) but uses
# modern PowerShell practices: CIM instead of WMI, typed configuration,
# parameterized SQL, structured logging, and Pester tests.

Set-StrictMode -Version Latest

# Dot-source the private implementation files. Order matters: helpers first,
# then checks, then the public entry points.
$script:ModuleRoot = $PSScriptRoot

. (Join-Path $PSScriptRoot 'Private\Configuration.ps1')
. (Join-Path $PSScriptRoot 'Private\Logging.ps1')
. (Join-Path $PSScriptRoot 'Private\Helpers.ps1')
. (Join-Path $PSScriptRoot 'Private\Checks.ps1')
. (Join-Path $PSScriptRoot 'Private\Remediation.ps1')
. (Join-Path $PSScriptRoot 'Private\Reporting.ps1')
. (Join-Path $PSScriptRoot 'Public\Invoke-ClientHealthCheck.ps1')
. (Join-Path $PSScriptRoot 'Public\Get-ClientHealthReport.ps1')
. (Join-Path $PSScriptRoot 'Public\New-ClientHealthLogObject.ps1')

Export-ModuleMember -Function @(
    'Invoke-ClientHealthCheck',
    'Get-ClientHealthConfig',
    'Test-ClientHealthConfig',
    'Get-ClientHealthReport',
    'New-ClientHealthLogObject'
)
