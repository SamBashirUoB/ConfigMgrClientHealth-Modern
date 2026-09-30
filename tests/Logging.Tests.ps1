# Pester tests for logging and helpers.
# Private functions are tested via InModuleScope so they run inside the module.

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $moduleRoot 'ConfigMgrClientHealth\ConfigMgrClientHealth.psd1') -Force
}

Describe 'Write-ClientHealthLog' {
    It 'writes a CMTrace-compatible log line' {
        InModuleScope ConfigMgrClientHealth {
            $logFile = Join-Path $TestDrive 'test.log'
            Write-ClientHealthLog -Message 'Test message' -LogFile $logFile
            $content = Get-Content -LiteralPath $logFile -Raw
            $content | Should -Match '<!\[LOG\[Test message\]LOG\]!>'
            $content | Should -Match 'time='
            $content | Should -Match 'date='
            $content | Should -Match 'component='
        }
    }

    It 'creates the log directory if missing' {
        InModuleScope ConfigMgrClientHealth {
            $logFile = Join-Path $TestDrive 'sub\dir\test.log'
            Write-ClientHealthLog -Message 'Test' -LogFile $logFile
            Test-Path -LiteralPath $logFile | Should -BeTrue
        }
    }
}

Describe 'Test-ClientHealthLogHistory' {
    It 'deletes the log when history is exceeded' {
        InModuleScope ConfigMgrClientHealth {
            $logFile = Join-Path $TestDrive 'history.log'
            for ($i = 0; $i -lt 12; $i++) {
                Write-ClientHealthLogObject -Log ([pscustomobject]@{ Hostname = 'test'; Timestamp = (Get-Date) }) -LogFile $logFile
            }
            Test-ClientHealthLogHistory -LogFile $logFile -MaxHistory 10
            Test-Path -LiteralPath $logFile | Should -BeFalse
        }
    }
}

Describe 'Get-ClientHealthComputerInfo' {
    It 'returns computer info' {
        InModuleScope ConfigMgrClientHealth {
            $info = Get-ClientHealthComputerInfo
            $info.Hostname | Should -Not -BeNullOrEmpty
            $info.OperatingSystem | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Get-ClientHealthOSName' {
    It 'returns a non-empty OS name' {
        InModuleScope ConfigMgrClientHealth {
            Get-ClientHealthOSName | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Get-ClientHealthPolicyTrigger' {
    It 'returns a GUID for a known trigger' {
        InModuleScope ConfigMgrClientHealth {
            Get-ClientHealthPolicyTrigger -Name 'HardwareInventory' | Should -Match '^\{[0-9a-fA-F-]{36}\}$'
        }
    }
}

Describe 'Test-ClientHealthIsAdministrator' {
    It 'returns a boolean' {
        InModuleScope ConfigMgrClientHealth {
            Test-ClientHealthIsAdministrator | Should -BeOfType [bool]
        }
    }
}
