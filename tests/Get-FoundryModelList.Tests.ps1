#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot/../src/PwshFoundry/PwshFoundry.psd1" -Force

    $script:mockModels = @(
        [PSCustomObject]@{
            name          = 'phi-3-mini'
            displayName   = 'Phi-3 Mini'
            providerType  = 'GenAI'
            version       = '3.0'
            promptTemplate = 'phi3'
            publisher     = 'Microsoft'
            task          = 'chat-completion'
            runtime       = [PSCustomObject]@{ deviceType = 'CPU' }
            maxOutputTokens = 4096
            extraProp     = 'should-be-excluded'
        }
        [PSCustomObject]@{
            name          = 'llama-3'
            displayName   = 'Llama 3'
            providerType  = 'GenAI'
            version       = '3.0'
            promptTemplate = 'llama3'
            publisher     = 'Meta'
            task          = 'chat-completion'
            runtime       = [PSCustomObject]@{ deviceType = 'GPU' }
            maxOutputTokens = 8192
            extraProp     = 'should-be-excluded'
        }
    )
}

Describe 'Get-FoundryModelList' {

    Context 'API returns a direct array' {
        BeforeAll {
            Mock -ModuleName PwshFoundry Get-FoundryServicePort { 5273 }
            Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest { $script:mockModels }
        }

        It 'returns an array' {
            $result = Get-FoundryModelList
            @($result).Count | Should -BeGreaterThan 0
        }

        It 'returns one entry per model' {
            $result = Get-FoundryModelList
            @($result).Count | Should -Be 2
        }

        It 'maps name correctly' {
            $result = Get-FoundryModelList
            $result[0].name | Should -Be 'phi-3-mini'
        }

        It 'maps displayName correctly' {
            $result = Get-FoundryModelList
            $result[0].displayName | Should -Be 'Phi-3 Mini'
        }

        It 'maps providerType correctly' {
            $result = Get-FoundryModelList
            $result[0].providerType | Should -Be 'GenAI'
        }

        It 'maps version correctly' {
            $result = Get-FoundryModelList
            $result[0].version | Should -Be '3.0'
        }

        It 'maps promptTemplate correctly' {
            $result = Get-FoundryModelList
            $result[0].promptTemplate | Should -Be 'phi3'
        }

        It 'maps publisher correctly' {
            $result = Get-FoundryModelList
            $result[0].publisher | Should -Be 'Microsoft'
        }

        It 'maps task correctly' {
            $result = Get-FoundryModelList
            $result[0].task | Should -Be 'chat-completion'
        }

        It 'flattens runtime.deviceType to deviceType' {
            $result = Get-FoundryModelList
            $result[0].deviceType | Should -Be 'CPU'
            $result[1].deviceType | Should -Be 'GPU'
        }

        It 'maps maxOutputTokens correctly' {
            $result = Get-FoundryModelList
            $result[0].maxOutputTokens | Should -Be 4096
        }

        It 'excludes properties not in the selection' {
            $result = Get-FoundryModelList
            $result[0].PSObject.Properties.Name | Should -Not -Contain 'extraProp'
            $result[0].PSObject.Properties.Name | Should -Not -Contain 'runtime'
        }
    }

    Context 'API returns a wrapped response with data property' {
        BeforeAll {
            Mock -ModuleName PwshFoundry Get-FoundryServicePort { 5273 }
            Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest {
                [PSCustomObject]@{ data = $script:mockModels }
            }
        }

        It 'unwraps the data property and returns models' {
            $result = Get-FoundryModelList
            @($result).Count | Should -Be 2
        }
    }

    Context 'Correct API call' {
        BeforeAll {
            Mock -ModuleName PwshFoundry Get-FoundryServicePort { 5273 }
            Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest { $script:mockModels }
        }

        It 'calls /foundry/list with GET' {
            Get-FoundryModelList
            Should -Invoke Invoke-FoundryApiRequest -ModuleName PwshFoundry -ParameterFilter {
                $Path -eq '/foundry/list' -and $Method -eq 'GET'
            }
        }

        It 'passes the port returned by Get-FoundryServicePort' {
            Get-FoundryModelList
            Should -Invoke Invoke-FoundryApiRequest -ModuleName PwshFoundry -ParameterFilter {
                $Port -eq 5273
            }
        }
    }

    Context 'No models available' {
        BeforeAll {
            Mock -ModuleName PwshFoundry Get-FoundryServicePort { 5273 }
            Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest { @() }
        }

        It 'returns an empty array' {
            $result = Get-FoundryModelList
            @($result).Count | Should -Be 0
        }
    }

    Context 'API returns null' {
        BeforeAll {
            Mock -ModuleName PwshFoundry Get-FoundryServicePort { 5273 }
            Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest { $null }
        }

        It 'returns an empty array' {
            $result = Get-FoundryModelList
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
            { Get-FoundryModelList } | Should -Throw -ExpectedMessage '*failed to start*'
        }
    }
}
