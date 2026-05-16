#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot/../src/PwshFoundry/PwshFoundry.psd1" -Force
    $script:message = New-FoundryMessage -UserPrompt 'Hello'
}

Describe 'New-FoundryChat' {

    Context 'Correct API call' {
        BeforeAll {
            Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest { [PSCustomObject]@{} }
        }

        It 'calls /v1/chat/completions with POST' {
            New-FoundryChat -Message $script:message -Model 'phi-3-mini'
            Should -Invoke Invoke-FoundryApiRequest -ModuleName PwshFoundry -ParameterFilter {
                $Path -eq '/v1/chat/completions' -and $Method -eq 'POST'
            }
        }
    }

    Context 'Return object mapping' {
        BeforeAll {
            Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest {
                [PSCustomObject]@{
                    id         = 'chatcmpl-abc123'
                    object     = 'chat.completion'
                    model      = 'phi-3-mini'
                    successful = $true
                    choices    = @(
                        [PSCustomObject]@{
                            message = [PSCustomObject]@{
                                role    = 'assistant'
                                content = 'Hello!'
                            }
                        }
                    )
                }
            }
            $script:result = New-FoundryChat -Message $script:message -Model 'phi-3-mini'
        }

        It 'maps id from the API response' {
            $script:result.id | Should -Be 'chatcmpl-abc123'
        }

        It 'maps object from the API response' {
            $script:result.object | Should -Be 'chat.completion'
        }

        It 'maps model from the API response' {
            $script:result.model | Should -Be 'phi-3-mini'
        }

        It 'maps successful from the API response' {
            $script:result.successful | Should -BeTrue
        }

        It 'maps message from choices[0].message' {
            $script:result.message.role    | Should -Be 'assistant'
            $script:result.message.content | Should -Be 'Hello!'
        }

        It 'returns a PSCustomObject' {
            $script:result.GetType().Name | Should -Be 'PSCustomObject'
        }
    }

    Context 'Body always includes required fields' {
        BeforeAll {
            Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest {
                $script:capturedBody = $Body
                [PSCustomObject]@{}
            }
            New-FoundryChat -Message $script:message -Model 'phi-3-mini'
        }

        It 'includes the model name' {
            $script:capturedBody['model'] | Should -Be 'phi-3-mini'
        }

        It 'includes the messages array from GetMessages()' {
            $script:capturedBody['messages'] | Should -Not -BeNullOrEmpty
            $script:capturedBody['messages'].Count | Should -Be 2
        }

        It 'includes the system message as first entry' {
            $script:capturedBody['messages'][0]['role'] | Should -Be 'system'
        }

        It 'includes the user message as second entry' {
            $script:capturedBody['messages'][1]['role']    | Should -Be 'user'
            $script:capturedBody['messages'][1]['content'] | Should -Be 'Hello'
        }

        It 'includes the user field' {
            $script:capturedBody.ContainsKey('user') | Should -BeTrue
        }
    }

    Context 'User parameter' {
        BeforeAll {
            Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest {
                $script:capturedBody = $Body
                [PSCustomObject]@{}
            }
        }

        It 'defaults to pwshChat when User is not supplied' {
            New-FoundryChat -Message $script:message -Model 'phi-3-mini'
            $script:capturedBody['user'] | Should -Be 'pwshChat'
        }

        It 'uses the supplied User value' {
            New-FoundryChat -Message $script:message -Model 'phi-3-mini' -User 'myAgent'
            $script:capturedBody['user'] | Should -Be 'myAgent'
        }
    }

    Context 'Optional sampling parameters are added when supplied' {
        BeforeAll {
            Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest {
                $script:capturedBody = $Body
                [PSCustomObject]@{}
            }
        }

        It 'includes temperature when supplied' {
            New-FoundryChat -Message $script:message -Model 'phi-3-mini' -Temperature 0.7
            $script:capturedBody.ContainsKey('temperature') | Should -BeTrue
            $script:capturedBody['temperature']             | Should -Be 0.7
        }

        It 'includes max_tokens when supplied' {
            New-FoundryChat -Message $script:message -Model 'phi-3-mini' -MaxTokens 512
            $script:capturedBody.ContainsKey('max_tokens') | Should -BeTrue
            $script:capturedBody['max_tokens']             | Should -Be 512
        }

        It 'includes top_p when supplied' {
            New-FoundryChat -Message $script:message -Model 'phi-3-mini' -TopP 0.9
            $script:capturedBody.ContainsKey('top_p') | Should -BeTrue
            $script:capturedBody['top_p']             | Should -Be 0.9
        }

        It 'includes presence_penalty when supplied' {
            New-FoundryChat -Message $script:message -Model 'phi-3-mini' -PresencePenalty 1.5
            $script:capturedBody.ContainsKey('presence_penalty') | Should -BeTrue
            $script:capturedBody['presence_penalty']             | Should -Be 1.5
        }

        It 'includes frequency_penalty when supplied' {
            New-FoundryChat -Message $script:message -Model 'phi-3-mini' -FrequencyPenalty -1.0
            $script:capturedBody.ContainsKey('frequency_penalty') | Should -BeTrue
            $script:capturedBody['frequency_penalty']             | Should -Be -1.0
        }
    }

    Context 'Optional sampling parameters are omitted when not supplied' {
        BeforeAll {
            Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest {
                $script:capturedBody = $Body
                [PSCustomObject]@{}
            }
            New-FoundryChat -Message $script:message -Model 'phi-3-mini'
        }

        It 'omits temperature' {
            $script:capturedBody.ContainsKey('temperature') | Should -BeFalse
        }

        It 'omits max_tokens' {
            $script:capturedBody.ContainsKey('max_tokens') | Should -BeFalse
        }

        It 'omits top_p' {
            $script:capturedBody.ContainsKey('top_p') | Should -BeFalse
        }

        It 'omits presence_penalty' {
            $script:capturedBody.ContainsKey('presence_penalty') | Should -BeFalse
        }

        It 'omits frequency_penalty' {
            $script:capturedBody.ContainsKey('frequency_penalty') | Should -BeFalse
        }
    }

    Context 'Parameter validation - Temperature' {
        It 'accepts boundary value 0.0' {
            { New-FoundryChat -Message $script:message -Model 'phi-3-mini' -Temperature 0.0 } | Should -Not -Throw
        }

        It 'accepts boundary value 2.0' {
            { New-FoundryChat -Message $script:message -Model 'phi-3-mini' -Temperature 2.0 } | Should -Not -Throw
        }

        It 'throws when Temperature is below 0' {
            { New-FoundryChat -Message $script:message -Model 'phi-3-mini' -Temperature -0.1 } | Should -Throw
        }

        It 'throws when Temperature is above 2' {
            { New-FoundryChat -Message $script:message -Model 'phi-3-mini' -Temperature 2.1 } | Should -Throw
        }
    }

    Context 'Parameter validation - MaxTokens' {
        It 'accepts boundary value 1' {
            { New-FoundryChat -Message $script:message -Model 'phi-3-mini' -MaxTokens 1 } | Should -Not -Throw
        }

        It 'accepts boundary value 2048' {
            { New-FoundryChat -Message $script:message -Model 'phi-3-mini' -MaxTokens 2048 } | Should -Not -Throw
        }

        It 'throws when MaxTokens is 0' {
            { New-FoundryChat -Message $script:message -Model 'phi-3-mini' -MaxTokens 0 } | Should -Throw
        }

        It 'throws when MaxTokens exceeds 2048' {
            { New-FoundryChat -Message $script:message -Model 'phi-3-mini' -MaxTokens 2049 } | Should -Throw
        }
    }

    Context 'Parameter validation - TopP' {
        It 'accepts boundary value 0.0' {
            { New-FoundryChat -Message $script:message -Model 'phi-3-mini' -TopP 0.0 } | Should -Not -Throw
        }

        It 'accepts boundary value 1.0' {
            { New-FoundryChat -Message $script:message -Model 'phi-3-mini' -TopP 1.0 } | Should -Not -Throw
        }

        It 'throws when TopP is below 0' {
            { New-FoundryChat -Message $script:message -Model 'phi-3-mini' -TopP -0.1 } | Should -Throw
        }

        It 'throws when TopP is above 1' {
            { New-FoundryChat -Message $script:message -Model 'phi-3-mini' -TopP 1.1 } | Should -Throw
        }
    }

    Context 'Parameter validation - PresencePenalty' {
        It 'accepts boundary value -2.0' {
            { New-FoundryChat -Message $script:message -Model 'phi-3-mini' -PresencePenalty -2.0 } | Should -Not -Throw
        }

        It 'accepts boundary value 2.0' {
            { New-FoundryChat -Message $script:message -Model 'phi-3-mini' -PresencePenalty 2.0 } | Should -Not -Throw
        }

        It 'throws when PresencePenalty is below -2' {
            { New-FoundryChat -Message $script:message -Model 'phi-3-mini' -PresencePenalty -2.1 } | Should -Throw
        }

        It 'throws when PresencePenalty is above 2' {
            { New-FoundryChat -Message $script:message -Model 'phi-3-mini' -PresencePenalty 2.1 } | Should -Throw
        }
    }

    Context 'Parameter validation - FrequencyPenalty' {
        It 'accepts boundary value -2.0' {
            { New-FoundryChat -Message $script:message -Model 'phi-3-mini' -FrequencyPenalty -2.0 } | Should -Not -Throw
        }

        It 'accepts boundary value 2.0' {
            { New-FoundryChat -Message $script:message -Model 'phi-3-mini' -FrequencyPenalty 2.0 } | Should -Not -Throw
        }

        It 'throws when FrequencyPenalty is below -2' {
            { New-FoundryChat -Message $script:message -Model 'phi-3-mini' -FrequencyPenalty -2.1 } | Should -Throw
        }

        It 'throws when FrequencyPenalty is above 2' {
            { New-FoundryChat -Message $script:message -Model 'phi-3-mini' -FrequencyPenalty 2.1 } | Should -Throw
        }
    }

    Context 'Mandatory parameters' {
        It 'throws when Message is not provided' {
            { New-FoundryChat -Model 'phi-3-mini' } | Should -Throw
        }

        It 'throws when Model is not provided' {
            { New-FoundryChat -Message $script:message } | Should -Throw
        }
    }
}
