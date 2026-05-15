#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot/../src/PwshFoundry/PwshFoundry.psd1" -Force
}

Describe 'Invoke-FoundryApiRequest' {

    Context 'URI construction' {
        BeforeAll {
            Mock -ModuleName PwshFoundry Invoke-RestMethod { [PSCustomObject]@{} }
        }

        It 'builds the URI from default host, port, and path' {
            InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -Port 5273 -Path '/v1/models' -Body @{} -Method GET
            }
            Should -Invoke Invoke-RestMethod -ModuleName PwshFoundry -ParameterFilter {
                $Uri -eq 'http://localhost:5273/v1/models'
            }
        }

        It 'strips a trailing slash from FoundryHost' {
            InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -FoundryHost 'http://localhost/' -Port 5273 -Path '/v1/models' -Body @{} -Method GET
            }
            Should -Invoke Invoke-RestMethod -ModuleName PwshFoundry -ParameterFilter {
                $Uri -eq 'http://localhost:5273/v1/models'
            }
        }

        It 'uses a custom FoundryHost and port' {
            InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -FoundryHost 'http://192.168.1.10' -Port 8080 -Path '/v1/agents' -Body @{} -Method GET
            }
            Should -Invoke Invoke-RestMethod -ModuleName PwshFoundry -ParameterFilter {
                $Uri -eq 'http://192.168.1.10:8080/v1/agents'
            }
        }
    }

    Context 'Request parameters' {
        BeforeAll {
            Mock -ModuleName PwshFoundry Invoke-RestMethod {
                [PSCustomObject]@{ id = 'model-1'; name = 'phi-3' }
            }
        }

        It 'returns the object from the REST API' {
            $result = InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -Port 5273 -Path '/v1/models' -Body @{} -Method GET
            }
            $result.id   | Should -Be 'model-1'
            $result.name | Should -Be 'phi-3'
        }

        It 'sets ContentType to application/json' {
            InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -Port 5273 -Path '/v1/models' -Body @{} -Method GET
            }
            Should -Invoke Invoke-RestMethod -ModuleName PwshFoundry -ParameterFilter {
                $ContentType -eq 'application/json'
            }
        }

        It 'serializes Body to a compressed JSON string' {
            InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -Port 5273 -Path '/v1/chat' -Body @{ prompt = 'hello' } -Method POST
            }
            Should -Invoke Invoke-RestMethod -ModuleName PwshFoundry -ParameterFilter {
                $Body -eq '{"prompt":"hello"}'
            }
        }

        It 'includes Headers when provided' {
            InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -Port 5273 -Path '/v1/models' -Body @{} -Method GET `
                    -Headers @{ Authorization = 'Bearer tok123' }
            }
            Should -Invoke Invoke-RestMethod -ModuleName PwshFoundry -ParameterFilter {
                $Headers['Authorization'] -eq 'Bearer tok123'
            }
        }

        It 'omits Headers when not provided' {
            InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -Port 5273 -Path '/v1/models' -Body @{} -Method GET
            }
            Should -Invoke Invoke-RestMethod -ModuleName PwshFoundry -ParameterFilter {
                $null -eq $Headers
            }
        }

        It 'accepts Method <Method>' -TestCases @(
            @{ Method = 'GET' }
            @{ Method = 'POST' }
            @{ Method = 'PUT' }
            @{ Method = 'HEAD' }
        ) {
            { InModuleScope PwshFoundry -ArgumentList $Method {
                param($m)
                Invoke-FoundryApiRequest -Port 5273 -Path '/v1/models' -Body @{} -Method $m
            }} | Should -Not -Throw
        }
    }

    Context 'REST API errors' {
        BeforeAll {
            Mock -ModuleName PwshFoundry Invoke-RestMethod {
                throw [System.Net.WebException]::new('Connection refused')
            }
        }

        It 'throws a terminating error when the REST call fails' {
            { InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -Port 5273 -Path '/v1/models' -Body @{} -Method GET
            }} | Should -Throw
        }

        It 'includes the method and URI in the error message' {
            { InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -Port 5273 -Path '/v1/models' -Body @{} -Method GET
            }} | Should -Throw -ExpectedMessage '*GET*localhost:5273*'
        }
    }

    Context 'Port auto-resolution' {
        BeforeAll {
            Mock -ModuleName PwshFoundry Get-FoundryServicePort { 9876 }
            Mock -ModuleName PwshFoundry Invoke-RestMethod { [PSCustomObject]@{} }
        }

        It 'calls Get-FoundryServicePort when Port is not supplied' {
            InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -Path '/v1/models' -Method GET
            }
            Should -Invoke Get-FoundryServicePort -ModuleName PwshFoundry -Times 1
        }

        It 'uses the port returned by Get-FoundryServicePort in the URI' {
            InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -Path '/v1/models' -Method GET
            }
            Should -Invoke Invoke-RestMethod -ModuleName PwshFoundry -ParameterFilter {
                $Uri -eq 'http://localhost:9876/v1/models'
            }
        }

        It 'does not call Get-FoundryServicePort when Port is supplied' {
            InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -Port 5273 -Path '/v1/models' -Method GET
            }
            Should -Invoke Get-FoundryServicePort -ModuleName PwshFoundry -Times 0
        }
    }

    Context 'Body omission' {
        BeforeAll {
            Mock -ModuleName PwshFoundry Invoke-RestMethod { [PSCustomObject]@{} }
        }

        It 'omits Body from the request when not supplied' {
            InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -Port 5273 -Path '/v1/models' -Method GET
            }
            Should -Invoke Invoke-RestMethod -ModuleName PwshFoundry -ParameterFilter {
                $null -eq $Body
            }
        }

        It 'includes Body in the request when supplied' {
            InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -Port 5273 -Path '/v1/chat' -Body @{ prompt = 'hi' } -Method POST
            }
            Should -Invoke Invoke-RestMethod -ModuleName PwshFoundry -ParameterFilter {
                $null -ne $Body
            }
        }
    }

    Context 'Parameter validation' {
        It 'rejects port 0' {
            { InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -Port 0 -Path '/v1/models' -Body @{} -Method GET
            }} | Should -Throw
        }

        It 'rejects port above 65535' {
            { InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -Port 70000 -Path '/v1/models' -Body @{} -Method GET
            }} | Should -Throw
        }

        It 'rejects a Path without a leading slash' {
            { InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -Port 5273 -Path 'v1/models' -Body @{} -Method GET
            }} | Should -Throw
        }

        It 'rejects an unsupported HTTP method' {
            { InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -Port 5273 -Path '/v1/models' -Body @{} -Method DELETE
            }} | Should -Throw
        }
    }
}
