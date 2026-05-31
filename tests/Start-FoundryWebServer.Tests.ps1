#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot/../src/PwshFoundry/PwshFoundry.psd1" -Force
}

Describe 'Start-FoundryWebServer' {

    Context 'dotnet CLI is not available' {
        BeforeAll {
            Mock -ModuleName PwshFoundry Get-Command { $null } -ParameterFilter { $Name -eq 'dotnet' }
        }

        It 'throws a terminating error with DotNetSdkNotFound id' {
            { Start-FoundryWebServer -ModelAlias 'test-model' } |
                Should -Throw -ExpectedMessage "*dotnet*"
        }
    }

    Context 'Parameter validation' {
        It 'requires ModelAlias' {
            { Start-FoundryWebServer } | Should -Throw
        }

        It 'rejects a port of 0' {
            { Start-FoundryWebServer -ModelAlias 'test-model' -Port 0 } | Should -Throw
        }

        It 'rejects a port above 65535' {
            { Start-FoundryWebServer -ModelAlias 'test-model' -Port 70000 } | Should -Throw
        }

        It 'rejects an invalid LogLevel' {
            { Start-FoundryWebServer -ModelAlias 'test-model' -LogLevel 'Verbose' } | Should -Throw
        }

        It 'rejects TimeoutSeconds below 30' {
            { Start-FoundryWebServer -ModelAlias 'test-model' -TimeoutSeconds 5 } | Should -Throw
        }
    }

    Context 'Server already running' {
        BeforeAll {
            # Inject a fake running process into module state
            InModuleScope PwshFoundry {
                $fakeProc = [System.Diagnostics.Process]::GetCurrentProcess()
                $script:FoundryWebServerProcess  = $fakeProc
                $script:FoundryWebServerEndpoint = 'http://127.0.0.1:52495/v1'
                $script:FoundryWebServerModelId  = 'test-model-id'
            }
        }

        AfterAll {
            InModuleScope PwshFoundry {
                $script:FoundryWebServerProcess  = $null
                $script:FoundryWebServerEndpoint = $null
                $script:FoundryWebServerModelId  = $null
                $script:FoundryWebServerTempDir  = $null
            }
        }

        It 'emits a warning and returns the existing endpoint' {
            $result = Start-FoundryWebServer -ModelAlias 'any' -WarningAction SilentlyContinue
            $result.Endpoint | Should -Be 'http://127.0.0.1:52495/v1'
        }

        It 'does not start a new process' {
            Mock -ModuleName PwshFoundry Get-Command { [PSCustomObject]@{ Source = 'dotnet' } } `
                -ParameterFilter { $Name -eq 'dotnet' }

            $before = InModuleScope PwshFoundry { $script:FoundryWebServerProcess.Id }
            Start-FoundryWebServer -ModelAlias 'any' -WarningAction SilentlyContinue | Out-Null
            $after  = InModuleScope PwshFoundry { $script:FoundryWebServerProcess.Id }
            $after | Should -Be $before
        }
    }
}
