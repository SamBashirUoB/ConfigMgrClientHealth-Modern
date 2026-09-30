# Pester tests for ConfigMgrClientHealth module.
# Run with: Invoke-Pester .\tests

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $moduleRoot 'ConfigMgrClientHealth\ConfigMgrClientHealth.psd1') -Force
}

Describe 'Module manifest' {
    It 'loads without errors' {
        { Import-Module (Join-Path $moduleRoot 'ConfigMgrClientHealth\ConfigMgrClientHealth.psd1') -Force -ErrorAction Stop } | Should -Not -Throw
    }

    It 'exports the expected public functions' {
        $expected = @(
            'Invoke-ClientHealthCheck',
            'Get-ClientHealthConfig',
            'Test-ClientHealthConfig',
            'Get-ClientHealthReport',
            'New-ClientHealthLogObject'
        )
        $exported = (Get-Command -Module ConfigMgrClientHealth).Name
        foreach ($name in $expected) {
            $exported | Should -Contain $name
        }
    }
}
