# Pester tests for configuration parsing.

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $moduleRoot 'ConfigMgrClientHealth\ConfigMgrClientHealth.psd1') -Force
    $sampleConfig = Join-Path $moduleRoot 'config.xml'
}

Describe 'Get-ClientHealthConfig' {
    It 'loads the sample config without error' {
        { $script:config = Get-ClientHealthConfig -Path $sampleConfig } | Should -Not -Throw
    }

    It 'returns a ClientHealthConfig object' {
        $config = Get-ClientHealthConfig -Path $sampleConfig
        $config | Should -BeOfType ClientHealthConfig
    }

    It 'parses the client section' {
        $config = Get-ClientHealthConfig -Path $sampleConfig
        $config.Client.SiteCode | Should -Not -BeNullOrEmpty
        $config.Client.Version | Should -Not -BeNullOrEmpty
        $config.Client.AutoUpgrade | Should -BeOfType [bool]
    }

    It 'parses services' {
        $config = Get-ClientHealthConfig -Path $sampleConfig
        $config.Services.Count | Should -BeGreaterThan 0
        $config.Services[0].Name | Should -Not -BeNullOrEmpty
    }

    It 'parses options with defaults' {
        $config = Get-ClientHealthConfig -Path $sampleConfig
        $config.Option.UpdatesEnabled | Should -BeOfType [bool]
        $config.Option.OSDiskFreeSpacePercent | Should -BeGreaterThan 0
    }

    It 'parses remediation' {
        $config = Get-ClientHealthConfig -Path $sampleConfig
        $config.Remediation.AdminShare | Should -BeOfType [bool]
    }

    It 'parses logging' {
        $config = Get-ClientHealthConfig -Path $sampleConfig
        $config.Logging.SQLEnabled | Should -BeOfType [bool]
    }

    It 'throws on a missing file' {
        { Get-ClientHealthConfig -Path 'Z:\does-not-exist.xml' } | Should -Throw
    }

    It 'throws on invalid XML' {
        $bad = Join-Path $TestDrive 'bad.xml'
        Set-Content -LiteralPath $bad -Value '<Configuration><Client>' -Encoding UTF8
        { Get-ClientHealthConfig -Path $bad } | Should -Throw
    }
}

Describe 'Test-ClientHealthConfig' {
    It 'returns true for the sample config' {
        Test-ClientHealthConfig -Path $sampleConfig | Should -BeTrue
    }

    It 'returns false for a missing file' {
        Test-ClientHealthConfig -Path 'Z:\does-not-exist.xml' | Should -BeFalse
    }
}
