#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot/../src/PwshFoundry/PwshFoundry.psd1" -Force
}

Describe 'Invoke-FoundryRank' {

    BeforeAll {
        Mock -ModuleName PwshFoundry Resolve-FoundryModel {
            [PSCustomObject]@{ alias = 'clm-v0.1-8b'; id = 'clm-v0.1-8b-generic-gpu:1'; cached = $true }
        }
        Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest {
            [PSCustomObject]@{
                model   = 'clm-v0.1-8b-generic-gpu:1'
                answers = @(
                    [PSCustomObject]@{ index = 0; prob = 0.91 }
                    [PSCustomObject]@{ index = 1; prob = 0.09 }
                )
            }
        }
    }

    Context 'Request body' {
        It 'calls the rank action with POST on the public catalog' {
            Invoke-FoundryRank -Model 'clm-v0.1-8b' -Answer 'a', 'b'
            Should -Invoke Invoke-FoundryApiRequest -ModuleName PwshFoundry -ParameterFilter {
                $Action -eq 'rank' -and $Method -eq 'POST' -and $Catalog -eq 'Public'
            }
        }

        It 'sends model, question, answers and context with the service keys' {
            Invoke-FoundryRank -Model 'clm-v0.1-8b' -Question 'Which one?' -Answer 'PowerShell', 'COBOL' `
                -Context @{ audience = 'sysadmin' }
            Should -Invoke Invoke-FoundryApiRequest -ModuleName PwshFoundry -ParameterFilter {
                ($Body | ConvertTo-Json -Depth 10 -Compress) -eq
                    '{"model":"clm-v0.1-8b","answers":["PowerShell","COBOL"],"question":"Which one?",' +
                    '"context":{"audience":"sysadmin"}}'
            }
        }

        It 'omits question, context and temperature unless given' {
            Invoke-FoundryRank -Model 'clm-v0.1-8b' -Answer 'a', 'b'
            Should -Invoke Invoke-FoundryApiRequest -ModuleName PwshFoundry -ParameterFilter {
                -not $Body.Contains('question') -and -not $Body.Contains('context') -and
                -not $Body.Contains('temperature')
            }
        }

        It 'sends temperature when given' {
            Invoke-FoundryRank -Model 'clm-v0.1-8b' -Answer 'a', 'b' -Temperature 2.5
            Should -Invoke Invoke-FoundryApiRequest -ModuleName PwshFoundry -ParameterFilter {
                $Body['temperature'] -eq 2.5
            }
        }

        It 'collects piped answers into a single request' {
            'one', 'two', 'three' | Invoke-FoundryRank -Model 'clm-v0.1-8b' -Question 'q'
            Should -Invoke Invoke-FoundryApiRequest -ModuleName PwshFoundry -Times 1 -Exactly -Scope It
            Should -Invoke Invoke-FoundryApiRequest -ModuleName PwshFoundry -ParameterFilter {
                ($Body.answers -join ',') -eq 'one,two,three'
            }
        }

        It 'passes -Catalog Local and skips the catalog check' {
            Invoke-FoundryRank -Model 'my-byom-ranker' -Answer 'a', 'b' -Catalog Local
            Should -Invoke Invoke-FoundryApiRequest -ModuleName PwshFoundry -ParameterFilter { $Catalog -eq 'Local' }
            Should -Invoke Resolve-FoundryModel -ModuleName PwshFoundry -Times 0 -Exactly -Scope It
        }
    }

    Context 'Output' {
        It 'returns a PwshFoundry.Ranking object' {
            $result = Invoke-FoundryRank -Model 'clm-v0.1-8b' -Question 'q' -Answer 'a', 'b'
            $result.PSObject.TypeNames[0] | Should -Be 'PwshFoundry.Ranking'
            $result.Model | Should -Be 'clm-v0.1-8b-generic-gpu:1'
            $result.Question | Should -Be 'q'
            $result.Answers | Should -Be @('a', 'b')
            $result.Result.answers[0].prob | Should -Be 0.91
        }

        It 'returns the raw response with -Raw' {
            $result = Invoke-FoundryRank -Model 'clm-v0.1-8b' -Answer 'a', 'b' -Raw
            $result.PSObject.TypeNames[0] | Should -Not -Be 'PwshFoundry.Ranking'
            $result.answers.Count | Should -Be 2
        }
    }

    Context 'Validation' {
        It 'rejects temperature <Value>' -TestCases @(@{ Value = 0 }, @{ Value = -1 }, @{ Value = 100.5 }) {
            { Invoke-FoundryRank -Model 'clm-v0.1-8b' -Answer 'a' -Temperature $Value } |
                Should -Throw -ExpectedMessage '*greater than 0 and at most 100*'
        }

        It 'accepts temperature 100' {
            { Invoke-FoundryRank -Model 'clm-v0.1-8b' -Answer 'a' -Temperature 100 } | Should -Not -Throw
        }

        It 'rejects an empty answer' {
            { Invoke-FoundryRank -Model 'clm-v0.1-8b' -Answer '' } | Should -Throw
        }

        It 'rejects an unknown model' {
            Mock -ModuleName PwshFoundry Resolve-FoundryModel { }
            { Invoke-FoundryRank -Model 'nope' -Answer 'a' } | Should -Throw -ErrorId 'FoundryModelNotFound*'
        }

        It 'rejects a model that is not downloaded' {
            Mock -ModuleName PwshFoundry Resolve-FoundryModel {
                [PSCustomObject]@{ alias = 'clm-v0.1-8b'; id = 'clm-v0.1-8b-generic-gpu:1'; cached = $false }
            }
            { Invoke-FoundryRank -Model 'clm-v0.1-8b' -Answer 'a' } | Should -Throw -ErrorId 'FoundryModelNotCached*'
        }

        It 'surfaces service errors as terminating errors' {
            Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest { throw 'HTTP 400 - expected text-ranking' }
            { Invoke-FoundryRank -Model 'clm-v0.1-8b' -Answer 'a' } | Should -Throw -ExpectedMessage '*text-ranking*'
        }
    }
}
