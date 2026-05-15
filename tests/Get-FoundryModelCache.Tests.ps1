#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot/../src/PwshFoundry/PwshFoundry.psd1" -Force
}

Describe 'Get-FoundryModelCache' {

    Context 'Models found in cache' {
        BeforeAll {
            Mock -ModuleName PwshFoundry Get-FoundryServicePort { 5273 }
            Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest {
                [PSCustomObject]@{
                    object = 'list'
                    data   = @(
                        [PSCustomObject]@{ id = 'phi-3';   object = 'model' }
                        [PSCustomObject]@{ id = 'llama-3'; object = 'model' }
                    )
                }
            }
        }

        It 'returns an array' {
            $result = Get-FoundryModelCache
            $result | Should -BeOfType [object]
            @($result).Count | Should -BeGreaterThan 0
        }

        It 'returns one entry per cached model' {
            $result = Get-FoundryModelCache
            @($result).Count | Should -Be 2
        }

        It 'returns the model objects from the data property' {
            $result = Get-FoundryModelCache
            $result[0].id | Should -Be 'phi-3'
            $result[1].id | Should -Be 'llama-3'
        }

        It 'calls the /openai/models path with GET' {
            Get-FoundryModelCache
            Should -Invoke Invoke-FoundryApiRequest -ModuleName PwshFoundry -ParameterFilter {
                $Path -eq '/openai/models' -and $Method -eq 'GET'
            }
        }

        It 'passes the port from Get-FoundryServicePort to the API call' {
            Get-FoundryModelCache
            Should -Invoke Invoke-FoundryApiRequest -ModuleName PwshFoundry -ParameterFilter {
                $Port -eq 5273
            }
        }
    }

    Context 'No models in cache' {
        BeforeAll {
            Mock -ModuleName PwshFoundry Get-FoundryServicePort { 5273 }
            Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest {
                [PSCustomObject]@{ object = 'list'; data = @() }
            }
        }

        It 'returns an empty array' {
            $result = Get-FoundryModelCache
            @($result).Count | Should -Be 0
        }
    }

    Context 'API returns null or no data property' {
        BeforeAll {
            Mock -ModuleName PwshFoundry Get-FoundryServicePort { 5273 }
            Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest { $null }
        }

        It 'returns an empty array instead of null' {
            $result = Get-FoundryModelCache
            $result | Should -Not -BeNullOrEmpty -ErrorAction SilentlyContinue
            @($result).Count | Should -Be 0
        }
    }

    Context 'Service is not running' {
        BeforeAll {
            Mock -ModuleName PwshFoundry Get-FoundryServicePort {
                throw [System.Exception]::new('Foundry service failed to start.')
            }
        }

        It 'propagates the error from Get-FoundryServicePort' {
            { Get-FoundryModelCache } | Should -Throw -ExpectedMessage '*failed to start*'
        }
    }
}
