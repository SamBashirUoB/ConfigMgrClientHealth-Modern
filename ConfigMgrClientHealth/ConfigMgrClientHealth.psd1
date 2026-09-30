@{
    RootModule           = 'ConfigMgrClientHealth.psm1'
    ModuleVersion        = '1.0.0'
    GUID                 = 'a1b2c3d4-0000-4000-8000-000000000001'
    Author               = 'Sam Bashir'
    CompanyName          = 'University of Birmingham'
    Copyright            = '(c) 2026. MIT License.'
    Description          = 'Modernized ConfigMgr (SCCM) Client Health. Validates and automatically remediates common Configuration Manager client issues on Windows endpoints. Modern implementation of the classic ConfigMgr Client Health tool by Anders Rodland.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport    = @(
        'Invoke-ClientHealthCheck',
        'Get-ClientHealthConfig',
        'Test-ClientHealthConfig',
        'Get-ClientHealthReport',
        'New-ClientHealthLogObject'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags         = @('ConfigMgr', 'SCCM', 'ClientHealth', 'Windows', 'Remediation')
            ProjectUri   = 'https://github.com/SamBashirUoB/ConfigMgrClientHealth-Modern'
            LicenseUri   = 'https://github.com/SamBashirUoB/ConfigMgrClientHealth-Modern/blob/main/LICENSE'
            ReleaseNotes = 'Modernized rewrite of ConfigMgr Client Health. See CHANGELOG.md.'
        }
    }
}
