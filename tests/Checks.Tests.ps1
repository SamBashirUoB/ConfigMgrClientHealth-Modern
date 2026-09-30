# Pester tests for the health check functions.
# Private functions are tested via InModuleScope so they run inside the module.

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $moduleRoot 'ConfigMgrClientHealth\ConfigMgrClientHealth.psd1') -Force
}

Describe 'New-ClientHealthLogObject' {
    It 'returns a log object with all expected fields' {
        $log = New-ClientHealthLogObject
        $log.Hostname | Should -Not -BeNullOrEmpty
        $log.Version | Should -Be '1.0.0'
        $log.Timestamp | Should -BeOfType [datetime]
    }
}

Describe 'Test-ClientHealthClientVersion' {
    It 'returns Error when version cannot be read' {
        InModuleScope ConfigMgrClientHealth {
            Mock -CommandName Get-ClientHealthClientVersion -MockWith { return $null }
            $result = Test-ClientHealthClientVersion -MinimumVersion '5.00.9128.1000'
            $result.Status | Should -Be 'Error'
        }
    }
}

Describe 'Test-ClientHealthPendingReboot' {
    It 'returns a result object' {
        InModuleScope ConfigMgrClientHealth {
            $result = Test-ClientHealthPendingReboot
            $result.Name | Should -Be 'PendingReboot'
            $result.Status | Should -BeIn @('OK', 'Warning')
        }
    }
}

Describe 'Test-ClientHealthMissingDrivers' {
    It 'returns a result object' {
        InModuleScope ConfigMgrClientHealth {
            $result = Test-ClientHealthMissingDrivers
            $result.Name | Should -Be 'Drivers'
            $result.Status | Should -BeIn @('OK', 'Warning')
        }
    }
}

Describe 'Test-ClientHealthAdminShare' {
    It 'returns a result object' {
        InModuleScope ConfigMgrClientHealth {
            $result = Test-ClientHealthAdminShare
            $result.Name | Should -Be 'AdminShare'
            $result.Status | Should -BeIn @('OK', 'Warning', 'Error')
        }
    }
}

Describe 'Test-ClientHealthServices' {
    It 'returns results for configured services' {
        InModuleScope ConfigMgrClientHealth {
            $svc = [ClientHealthServiceConfig]::new()
            $svc.Name = 'ccmexec'
            $svc.StartupType = 'Automatic'
            $svc.State = 'Running'
            $results = Test-ClientHealthServices -Services @($svc)
            $results | Should -Not -BeNullOrEmpty
        }
    }
}
