#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot/../src/PwshFoundry/PwshFoundry.psd1" -Force
}

Describe 'New-FoundryTool' {

    Context 'Request object shape' {
        BeforeAll {
            $script:tool = New-FoundryTool -Name 'Get-Weather' `
                -Description 'Returns the weather for a city' `
                -Parameters @{ City = @{ type = 'string'; description = 'City name' } } `
                -Required 'City' `
                -Handler { param($City) "Sunny in $City" }
            $script:requestObject = $script:tool.ToRequestObject()
        }

        It 'has type function' {
            $script:requestObject['type'] | Should -Be 'function'
        }

        It 'maps the function name' {
            $script:requestObject['function']['name'] | Should -Be 'Get-Weather'
        }

        It 'maps the function description' {
            $script:requestObject['function']['description'] | Should -Be 'Returns the weather for a city'
        }

        It 'wraps parameters in an object schema' {
            $script:requestObject['function']['parameters']['type'] | Should -Be 'object'
            $script:requestObject['function']['parameters']['properties']['City']['type'] | Should -Be 'string'
        }

        It 'maps the required list' {
            $script:requestObject['function']['parameters']['required'] | Should -Be @('City')
        }
    }

    Context 'Invoke' {
        It 'splats the arguments as named parameters' {
            $tool = New-FoundryTool -Name 'Get-Weather' -Description 'weather' `
                -Parameters @{ City = @{ type = 'string' } } `
                -Handler { param($City) "Sunny in $City" }
            $tool.Invoke(@{ City = 'Paris' }) | Should -Be 'Sunny in Paris'
        }

        It 'returns an empty string when the handler returns nothing' {
            $tool = New-FoundryTool -Name 'Do-Nothing' -Description 'noop' -Handler { $null }
            $tool.Invoke(@{}) | Should -Be ''
        }

        It 'serializes non-string output to JSON' {
            $tool = New-FoundryTool -Name 'Get-Data' -Description 'data' `
                -Handler { @{ answer = 42 } }
            $tool.Invoke(@{}) | Should -Match '"answer"\s*:\s*42'
        }

        It 'returns an error string instead of throwing when the handler fails' {
            $tool = New-FoundryTool -Name 'Fail-Tool' -Description 'always fails' `
                -Handler { throw 'boom' }
            $tool.Invoke(@{}) | Should -Match 'Tool execution failed: .*boom'
        }

        It 'handles a null arguments table' {
            $tool = New-FoundryTool -Name 'Do-Nothing' -Description 'noop' -Handler { 'ok' }
            $tool.Invoke($null) | Should -Be 'ok'
        }
    }

    Context 'Validation' {
        It 'throws when a required name is not defined in Parameters' {
            {
                New-FoundryTool -Name 'Get-Weather' -Description 'weather' `
                    -Parameters @{ City = @{ type = 'string' } } `
                    -Required 'Country' `
                    -Handler { 'x' }
            } | Should -Throw "*Required parameter 'Country'*"
        }

        It 'throws when Name is not provided' {
            { New-FoundryTool -Description 'weather' -Handler { 'x' } } | Should -Throw
        }

        It 'throws when Description is not provided' {
            { New-FoundryTool -Name 'Get-Weather' -Handler { 'x' } } | Should -Throw
        }

        It 'throws when Handler is not provided' {
            { New-FoundryTool -Name 'Get-Weather' -Description 'weather' } | Should -Throw
        }
    }
}
