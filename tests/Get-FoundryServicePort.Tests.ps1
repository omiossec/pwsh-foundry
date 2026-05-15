#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot/../src/PwshFoundry/PwshFoundry.psd1" -Force
}

Describe 'Get-FoundryServicePort' {

    Context 'Service already running' {
        BeforeAll {
            Mock -ModuleName PwshFoundry Invoke-FoundryCli {
                'Foundry service is running at http://localhost:5273'
            }
        }

        It 'returns the port as an integer' {
            $port = InModuleScope PwshFoundry { Get-FoundryServicePort }
            $port | Should -Be 5273
        }

        It 'returns an [int]' {
            $port = InModuleScope PwshFoundry { Get-FoundryServicePort }
            $port | Should -BeOfType [int]
        }

        It 'calls service status once and does not call service start' {
            InModuleScope PwshFoundry { Get-FoundryServicePort }
            Should -Invoke Invoke-FoundryCli -ModuleName PwshFoundry -Times 1 -ParameterFilter {
                $Arguments -contains 'status'
            }
            Should -Invoke Invoke-FoundryCli -ModuleName PwshFoundry -Times 0 -ParameterFilter {
                $Arguments -contains 'start'
            }
        }
    }

    Context 'Service not running — starts successfully' {
        BeforeAll {
            $script:callCount = 0
            Mock -ModuleName PwshFoundry Invoke-FoundryCli {
                if ($Arguments -contains 'start') { return }
                $script:callCount++
                if ($script:callCount -eq 1) {
                    return 'Foundry service is not running'
                }
                return 'Foundry service is running at http://localhost:5273'
            }
        }

        It 'returns the port after starting the service' {
            $port = InModuleScope PwshFoundry { Get-FoundryServicePort }
            $port | Should -Be 5273
        }

        It 'calls service start exactly once' {
            InModuleScope PwshFoundry { Get-FoundryServicePort }
            Should -Invoke Invoke-FoundryCli -ModuleName PwshFoundry -ParameterFilter {
                $Arguments -contains 'start'
            }
        }

        It 'calls service status twice' {
            InModuleScope PwshFoundry { Get-FoundryServicePort }
            Should -Invoke Invoke-FoundryCli -ModuleName PwshFoundry -Times 2 -ParameterFilter {
                $Arguments -contains 'status'
            }
        }
    }

    Context 'Service fails to start' {
        BeforeAll {
            Mock -ModuleName PwshFoundry Invoke-FoundryCli {
                if ($Arguments -contains 'start') { return }
                return 'Foundry service is not running'
            }
        }

        It 'throws a terminating error' {
            { InModuleScope PwshFoundry { Get-FoundryServicePort } } | Should -Throw
        }

        It 'error message indicates the service failed to start' {
            { InModuleScope PwshFoundry { Get-FoundryServicePort } } |
                Should -Throw -ExpectedMessage '*failed to start*'
        }
    }

    Context 'Status output contains no URI' {
        BeforeAll {
            Mock -ModuleName PwshFoundry Invoke-FoundryCli {
                'Foundry service is running but endpoint unknown'
            }
        }

        It 'throws a terminating error' {
            { InModuleScope PwshFoundry { Get-FoundryServicePort } } | Should -Throw
        }

        It 'error message indicates the port could not be determined' {
            { InModuleScope PwshFoundry { Get-FoundryServicePort } } |
                Should -Throw -ExpectedMessage '*port*'
        }
    }

    Context 'Port extraction' {
        It 'extracts the correct port from multi-line status output' -TestCases @(
            @{ Port = 5273 }
            @{ Port = 8080 }
            @{ Port = 11434 }
        ) {
            Mock -ModuleName PwshFoundry Invoke-FoundryCli {
                "Foundry service is running`nEndpoint: http://localhost:$Port`nStatus: OK"
            }
            $result = InModuleScope PwshFoundry -ArgumentList $Port {
                param($p)
                Get-FoundryServicePort
            }
            $result | Should -Be $Port
        }
    }
}
