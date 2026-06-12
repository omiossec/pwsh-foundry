#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot/../src/PwshFoundry/PwshFoundry.psd1" -Force
}

Describe 'Stop-FoundryWebServer' {

    Context 'No server is tracked' {
        BeforeAll {
            InModuleScope PwshFoundry { $script:FoundryWebServerProcess = $null }
        }

        It 'emits a warning and does not throw' {
            { Stop-FoundryWebServer -WarningAction SilentlyContinue } | Should -Not -Throw
        }
    }

    Context 'Server process has already exited' {
        BeforeAll {
            InModuleScope PwshFoundry {
                # Use a process that has definitely exited
                $p = Start-Process -FilePath 'cmd' -ArgumentList '/c exit 0' -PassThru -WindowStyle Hidden
                $p.WaitForExit(3000) | Out-Null
                $script:FoundryWebServerProcess  = $p
                $script:FoundryWebServerEndpoint = 'http://127.0.0.1:52495/v1'
                $script:FoundryWebServerModelId  = 'test-model'
                $script:FoundryWebServerTempDir  = $null
            }
        }

        It 'does not throw' {
            { Stop-FoundryWebServer } | Should -Not -Throw
        }

        It 'clears module state after stop' {
            $endpoint = InModuleScope PwshFoundry { $script:FoundryWebServerEndpoint }
            $endpoint | Should -BeNullOrEmpty
        }
    }

    Context 'Clears all module state variables' {
        BeforeAll {
            InModuleScope PwshFoundry {
                $p = Start-Process -FilePath 'cmd' -ArgumentList '/c exit 0' -PassThru -WindowStyle Hidden
                $p.WaitForExit(3000) | Out-Null
                $script:FoundryWebServerProcess  = $p
                $script:FoundryWebServerEndpoint = 'http://127.0.0.1:52495/v1'
                $script:FoundryWebServerModelId  = 'some-model'
                # Non-existent path — avoids Remove-Item touching real directories
                $script:FoundryWebServerTempDir  = Join-Path ([System.IO.Path]::GetTempPath()) "FoundryTest_$(New-Guid)"
            }
            Stop-FoundryWebServer
        }

        It 'clears FoundryWebServerProcess' {
            InModuleScope PwshFoundry { $script:FoundryWebServerProcess } | Should -BeNullOrEmpty
        }

        It 'clears FoundryWebServerEndpoint' {
            InModuleScope PwshFoundry { $script:FoundryWebServerEndpoint } | Should -BeNullOrEmpty
        }

        It 'clears FoundryWebServerModelId' {
            InModuleScope PwshFoundry { $script:FoundryWebServerModelId } | Should -BeNullOrEmpty
        }

        It 'clears FoundryWebServerTempDir' {
            InModuleScope PwshFoundry { $script:FoundryWebServerTempDir } | Should -BeNullOrEmpty
        }
    }
}
