#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot/../src/PwshFoundry/PwshFoundry.psd1" -Force

    # Pester executes module-scoped mock bodies in the module's scope, so the fake
    # response is built by a function the mocks can reach through the global scope.
    function global:New-FakeEmbeddingResponse {
        [PSCustomObject]@{
            object = 'list'
            model  = 'qwen3-embedding-0.6b'
            data   = @(
                [PSCustomObject]@{ object = 'embedding'; index = 1; embedding = @(0.0, 1.0, 0.0) }
                [PSCustomObject]@{ object = 'embedding'; index = 0; embedding = @(1.0, 0.0, 0.0) }
            )
            usage  = [PSCustomObject]@{ prompt_tokens = 8; total_tokens = 8 }
        }
    }
}

AfterAll {
    Remove-Item -Path 'Function:\New-FakeEmbeddingResponse' -ErrorAction SilentlyContinue
}

Describe 'New-FoundryEmbedding' {

    Context 'Model validation' {
        BeforeAll {
            Mock -ModuleName PwshFoundry Test-FoundryModelName { $false }
        }

        It 'throws FoundryModelNotFound for an unknown model' {
            { New-FoundryEmbedding -Model 'no-such-model' -Text 'hello' -ErrorAction Stop } |
                Should -Throw -ErrorId 'FoundryModelNotFound,New-FoundryEmbedding'
        }
    }

    Context 'Correct API call' {
        BeforeAll {
            Mock -ModuleName PwshFoundry Test-FoundryModelName { $true }
            Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest {
                @('qwen3-embedding-0.6b:1')
            } -ParameterFilter { $Action -eq 'models-loaded' }
            Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest {
                New-FakeEmbeddingResponse
            } -ParameterFilter { $Action -eq 'embeddings' }
        }

        It 'calls the embeddings action with POST' {
            New-FoundryEmbedding -Model 'qwen3-embedding-0.6b' -Text 'hello'
            Should -Invoke Invoke-FoundryApiRequest -ModuleName PwshFoundry -ParameterFilter {
                $Action -eq 'embeddings' -and $Method -eq 'POST'
            }
        }

        It 'sends model and input in the body' {
            New-FoundryEmbedding -Model 'qwen3-embedding-0.6b' -Text 'first', 'second'
            Should -Invoke Invoke-FoundryApiRequest -ModuleName PwshFoundry -ParameterFilter {
                $Action -eq 'embeddings' -and
                $Body.model -eq 'qwen3-embedding-0.6b' -and
                $Body.input.Count -eq 2 -and
                $Body.input[0] -eq 'first' -and
                $Body.input[1] -eq 'second'
            }
        }

        It 'does not load the model when the versioned id is already loaded' {
            New-FoundryEmbedding -Model 'qwen3-embedding-0.6b' -Text 'hello'
            Should -Invoke Invoke-FoundryApiRequest -ModuleName PwshFoundry -Times 0 -ParameterFilter {
                $Action -eq 'model-load'
            }
        }

        It 'batches pipeline input into a single request' {
            'first', 'second', 'third' | New-FoundryEmbedding -Model 'qwen3-embedding-0.6b'
            Should -Invoke Invoke-FoundryApiRequest -ModuleName PwshFoundry -Times 1 -Exactly -ParameterFilter {
                $Action -eq 'embeddings'
            }
            Should -Invoke Invoke-FoundryApiRequest -ModuleName PwshFoundry -ParameterFilter {
                $Action -eq 'embeddings' -and $Body.input.Count -eq 3
            }
        }
    }

    Context 'Model loading' {
        BeforeAll {
            Mock -ModuleName PwshFoundry Test-FoundryModelName { $true }
            Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest {
                @('some-other-model')
            } -ParameterFilter { $Action -eq 'models-loaded' }
            Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest { } -ParameterFilter { $Action -eq 'model-load' }
            Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest {
                New-FakeEmbeddingResponse
            } -ParameterFilter { $Action -eq 'embeddings' }
        }

        It 'loads the model when it is not loaded' {
            New-FoundryEmbedding -Model 'qwen3-embedding-0.6b' -Text 'hello'
            Should -Invoke Invoke-FoundryApiRequest -ModuleName PwshFoundry -ParameterFilter {
                $Action -eq 'model-load' -and $PathParameters.name -eq 'qwen3-embedding-0.6b'
            }
        }
    }

    Context 'Output mapping' {
        BeforeAll {
            Mock -ModuleName PwshFoundry Test-FoundryModelName { $true }
            Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest {
                @('qwen3-embedding-0.6b')
            } -ParameterFilter { $Action -eq 'models-loaded' }
            Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest {
                New-FakeEmbeddingResponse
            } -ParameterFilter { $Action -eq 'embeddings' }

            $script:result = New-FoundryEmbedding -Model 'qwen3-embedding-0.6b' -Text 'first', 'second'
        }

        It 'emits one object per input text' {
            $script:result.Count | Should -Be 2
        }

        It 'orders results by index and pairs them with the matching text' {
            $script:result[0].Index | Should -Be 0
            $script:result[0].Text  | Should -Be 'first'
            $script:result[1].Index | Should -Be 1
            $script:result[1].Text  | Should -Be 'second'
        }

        It 'maps the embedding vector as double[]' {
            $script:result[0].Embedding | Should -Be @(1.0, 0.0, 0.0)
            $script:result[0].Embedding[0] | Should -BeOfType [double]
        }

        It 'maps model and usage from the API response' {
            $script:result[0].Model | Should -Be 'qwen3-embedding-0.6b'
            $script:result[0].Usage.total_tokens | Should -Be 8
        }
    }
}
