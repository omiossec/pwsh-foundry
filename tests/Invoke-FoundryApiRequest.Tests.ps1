#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot/../src/PwshFoundry/PwshFoundry.psd1" -Force
}

Describe 'Invoke-FoundryApiRequest' {

    BeforeAll {
        Mock -ModuleName PwshFoundry Get-FoundryVersion {
            [PSCustomObject]@{ Source = 'CLI'; Version = '0.14.0'; Message = '0.14.0' }
        }
        Mock -ModuleName PwshFoundry Get-FoundryServicePort { 9876 }
    }

    Context 'URI construction' {
        BeforeAll {
            Mock -ModuleName PwshFoundry Invoke-RestMethod { [PSCustomObject]@{} }
        }

        It 'maps <Action> to <Path>' -TestCases @(
            @{ Action = 'status';          Path = '/status' }
            @{ Action = 'shutdown';        Path = '/shutdown' }
            @{ Action = 'model-list';      Path = '/v1/models' }
            @{ Action = 'models-loaded';   Path = '/models/loaded' }
            @{ Action = 'chat';            Path = '/v1/chat/completions' }
            @{ Action = 'decision';        Path = '/v1/systemone' }
            @{ Action = 'rank';            Path = '/v1/rank' }
            @{ Action = 'response-create'; Path = '/v1/responses' }
            @{ Action = 'response-list';   Path = '/v1/responses' }
        ) {
            InModuleScope PwshFoundry -Parameters @{ a = $Action } {
                Invoke-FoundryApiRequest -Port 5273 -Action $a -Method GET
            }
            Should -Invoke Invoke-RestMethod -ModuleName PwshFoundry -ParameterFilter {
                $Uri -eq "http://localhost:5273$Path"
            }
        }

        It 'fills and escapes path parameters' {
            InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -Port 5273 -Action 'model-get' -Method GET `
                    -PathParameters @{ name = 'qwen3-0.6b-generic-gpu:2' }
            }
            Should -Invoke Invoke-RestMethod -ModuleName PwshFoundry -ParameterFilter {
                $Uri -eq 'http://localhost:5273/v1/models/qwen3-0.6b-generic-gpu%3A2'
            }
        }

        It 'builds the input_items route for a response id' {
            InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -Port 5273 -Action 'response-input-items' -Method GET `
                    -PathParameters @{ id = 'resp_123' }
            }
            Should -Invoke Invoke-RestMethod -ModuleName PwshFoundry -ParameterFilter {
                $Uri -eq 'http://localhost:5273/v1/responses/resp_123/input_items'
            }
        }

        It 'strips a trailing slash from FoundryHost' {
            InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -FoundryHost 'http://127.0.0.1/' -Port 5273 -Action 'status' -Method GET
            }
            Should -Invoke Invoke-RestMethod -ModuleName PwshFoundry -ParameterFilter {
                $Uri -eq 'http://127.0.0.1:5273/status'
            }
        }
    }

    Context 'Query string' {
        BeforeAll {
            Mock -ModuleName PwshFoundry Invoke-RestMethod { [PSCustomObject]@{} }
        }

        It 'appends sorted, escaped query parameters and skips nulls' {
            InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -Port 5273 -Action 'response-list' -Method GET `
                    -Query @{ limit = 5; order = 'asc'; after = $null }
            }
            Should -Invoke Invoke-RestMethod -ModuleName PwshFoundry -ParameterFilter {
                $Uri -eq 'http://localhost:5273/v1/responses?limit=5&order=asc'
            }
        }

        It 'sends booleans as lowercase' {
            InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -Port 5273 -Action 'models-loaded' -Method GET -Query @{ details = $true }
            }
            Should -Invoke Invoke-RestMethod -ModuleName PwshFoundry -ParameterFilter {
                $Uri -eq 'http://localhost:5273/models/loaded?details=true'
            }
        }

        It 'escapes query values' {
            InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -Port 5273 -Action 'model-load' -Method GET `
                    -PathParameters @{ name = 'm' } -Query @{ expected_model_path = 'C:\a b' }
            }
            Should -Invoke Invoke-RestMethod -ModuleName PwshFoundry -ParameterFilter {
                $Uri -eq 'http://localhost:5273/models/load/m?expected_model_path=C%3A%5Ca%20b'
            }
        }
    }

    Context 'Catalog' {
        BeforeAll {
            Mock -ModuleName PwshFoundry Invoke-RestMethod { [PSCustomObject]@{} }
        }

        It 'prefixes /catalogs/local for the Local catalog' {
            InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -Port 5273 -Action 'rank' -Method POST -Body @{} -Catalog Local
            }
            Should -Invoke Invoke-RestMethod -ModuleName PwshFoundry -ParameterFilter {
                $Uri -eq 'http://localhost:5273/catalogs/local/v1/rank'
            }
        }

        It 'rejects the Local catalog for root-only route <Action>' -TestCases @(
            @{ Action = 'status' }
            @{ Action = 'shutdown' }
        ) {
            { InModuleScope PwshFoundry -Parameters @{ a = $Action } {
                Invoke-FoundryApiRequest -Port 5273 -Action $a -Method GET -Catalog Local
            } } | Should -Throw -ErrorId 'FoundryCatalogNotSupported*'
        }
    }

    Context 'Version gating' {
        BeforeAll {
            Mock -ModuleName PwshFoundry Invoke-RestMethod { [PSCustomObject]@{} }
        }

        It 'uses the pre-0.10 route on an old CLI' {
            Mock -ModuleName PwshFoundry Get-FoundryVersion {
                [PSCustomObject]@{ Source = 'CLI'; Version = '0.9.0'; Message = '0.9.0' }
            }
            InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -Port 5273 -Action 'status' -Method GET
            }
            Should -Invoke Invoke-RestMethod -ModuleName PwshFoundry -ParameterFilter {
                $Uri -eq 'http://localhost:5273/openai/status'
            }
        }

        It 'rejects a 0.14 action on CLI 0.13' {
            Mock -ModuleName PwshFoundry Get-FoundryVersion {
                [PSCustomObject]@{ Source = 'CLI'; Version = '0.13.0'; Message = '0.13.0' }
            }
            { InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -Port 5273 -Action 'decision' -Method POST -Body @{}
            } } | Should -Throw -ExpectedMessage '*requires Foundry Local 0.14.0*'
        }

        It 'allows a 0.14 action in SDK mode' {
            Mock -ModuleName PwshFoundry Get-FoundryVersion {
                [PSCustomObject]@{ Source = 'SDK'; Version = $null; Message = 'SDK' }
            }
            { InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -Port 5273 -Action 'decision' -Method POST -Body @{}
            } } | Should -Not -Throw
        }

        It 'rejects an action removed in 0.10 (<Action>)' -TestCases @(
            @{ Action = 'tokenizer' }
            @{ Action = 'model-download' }
        ) {
            { InModuleScope PwshFoundry -Parameters @{ a = $Action } {
                Invoke-FoundryApiRequest -Port 5273 -Action $a -Method POST
            } } | Should -Throw -ErrorId 'FoundryActionNotSupported*'
        }
    }

    Context 'Request parameters' {
        BeforeAll {
            Mock -ModuleName PwshFoundry Invoke-RestMethod { [PSCustomObject]@{ id = 'model-1' } }
        }

        It 'returns the object from the REST API' {
            $result = InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -Port 5273 -Action 'model-list' -Method GET
            }
            $result.id | Should -Be 'model-1'
        }

        It 'serializes Body to compressed JSON with a JSON content type' {
            InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -Port 5273 -Action 'chat' -Method POST -Body @{ prompt = 'hello' }
            }
            Should -Invoke Invoke-RestMethod -ModuleName PwshFoundry -ParameterFilter {
                $Body -eq '{"prompt":"hello"}' -and $ContentType -eq 'application/json'
            }
        }

        It 'omits Body when not supplied' {
            InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -Port 5273 -Action 'model-list' -Method GET
            }
            Should -Invoke Invoke-RestMethod -ModuleName PwshFoundry -ParameterFilter { $null -eq $Body }
        }

        It 'includes Headers when provided' {
            InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -Port 5273 -Action 'model-list' -Method GET `
                    -Headers @{ Authorization = 'Bearer tok123' }
            }
            Should -Invoke Invoke-RestMethod -ModuleName PwshFoundry -ParameterFilter {
                $Headers['Authorization'] -eq 'Bearer tok123'
            }
        }

        It 'accepts the DELETE method' {
            InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -Port 5273 -Action 'response-delete' -Method DELETE `
                    -PathParameters @{ id = 'resp_1' }
            }
            Should -Invoke Invoke-RestMethod -ModuleName PwshFoundry -ParameterFilter {
                $Method -eq 'DELETE' -and $Uri -eq 'http://localhost:5273/v1/responses/resp_1'
            }
        }
    }

    Context 'Port auto-resolution' {
        BeforeAll {
            Mock -ModuleName PwshFoundry Invoke-RestMethod { [PSCustomObject]@{} }
        }

        It 'uses Get-FoundryServicePort when Port is not supplied' {
            InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -Action 'model-list' -Method GET
            }
            Should -Invoke Get-FoundryServicePort -ModuleName PwshFoundry -Times 1 -Exactly
            Should -Invoke Invoke-RestMethod -ModuleName PwshFoundry -ParameterFilter {
                $Uri -eq 'http://localhost:9876/v1/models'
            }
        }

        It 'does not call Get-FoundryServicePort when Port is supplied' {
            InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -Port 5273 -Action 'model-list' -Method GET
            }
            Should -Invoke Get-FoundryServicePort -ModuleName PwshFoundry -Times 0 -Exactly
        }
    }

    Context 'REST API errors' {
        It 'includes the method and URI when the connection fails' {
            Mock -ModuleName PwshFoundry Invoke-RestMethod {
                throw [System.Net.Http.HttpRequestException]::new('Connection refused')
            }
            { InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -Port 5273 -Action 'model-list' -Method GET
            } } | Should -Throw -ExpectedMessage '*GET http://localhost:5273/v1/models*Connection refused*'
        }

        It 'surfaces the message and code of the OpenAI error envelope' {
            Mock -ModuleName PwshFoundry Invoke-RestMethod {
                $record = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Response status code does not indicate success: 404'),
                    'WebCmdletWebResponseException',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $null
                )
                $record.ErrorDetails = '{"error":{"message":"The response ''r1'' does not exist.",' +
                    '"type":"invalid_request_error","param":"id","code":"response_not_found"}}'
                throw $record
            }
            { InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -Port 5273 -Action 'response-get' -Method GET -PathParameters @{ id = 'r1' }
            } } | Should -Throw -ExpectedMessage "*The response 'r1' does not exist.*(response_not_found)*"
        }

        It 'keeps a non-JSON error body as the server response' {
            Mock -ModuleName PwshFoundry Invoke-RestMethod {
                $record = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Bad Request'),
                    'WebCmdletWebResponseException',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $null
                )
                $record.ErrorDetails = 'plain text failure'
                throw $record
            }
            { InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -Port 5273 -Action 'chat' -Method POST -Body @{}
            } } | Should -Throw -ExpectedMessage '*Server response: plain text failure*'
        }

        It 'uses the FoundryApiRequestError error id' {
            Mock -ModuleName PwshFoundry Invoke-RestMethod { throw 'boom' }
            { InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -Port 5273 -Action 'model-list' -Method GET
            } } | Should -Throw -ErrorId 'FoundryApiRequestError*'
        }
    }

    Context 'Parameter validation' {
        It 'rejects port <Port>' -TestCases @(@{ Port = 0 }, @{ Port = 70000 }) {
            { InModuleScope PwshFoundry -Parameters @{ p = $Port } {
                Invoke-FoundryApiRequest -Port $p -Action 'status' -Method GET
            } } | Should -Throw
        }

        It 'rejects an unknown action' {
            { InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -Port 5273 -Action 'nope' -Method GET
            } } | Should -Throw
        }

        It 'rejects an unsupported HTTP method' {
            { InModuleScope PwshFoundry {
                Invoke-FoundryApiRequest -Port 5273 -Action 'status' -Method PATCH
            } } | Should -Throw
        }
    }
}
