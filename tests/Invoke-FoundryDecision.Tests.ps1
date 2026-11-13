#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot/../src/PwshFoundry/PwshFoundry.psd1" -Force
}

Describe 'Invoke-FoundryDecision' {

    BeforeAll {
        Mock -ModuleName PwshFoundry Resolve-FoundryModel {
            [PSCustomObject]@{ alias = 'kev-0.8b'; id = 'kev-0.8b-generic-gpu:1'; cached = $true }
        }
        Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest {
            [PSCustomObject]@{
                model   = 'kev-0.8b-generic-gpu:1'
                answers = [PSCustomObject]@{ billing = 0.97 }
                usage   = [PSCustomObject]@{ billing_units = 0 }
            }
        }
        $state = @{ ticket = 'I was charged twice' }
    }

    Context 'Request body' {
        It 'calls the decision action with POST on the public catalog' {
            Invoke-FoundryDecision -Model 'kev-0.8b' -State $state -Predicate @{ billing = 'About billing?' }
            Should -Invoke Invoke-FoundryApiRequest -ModuleName PwshFoundry -ParameterFilter {
                $Action -eq 'decision' -and $Method -eq 'POST' -and $Catalog -eq 'Public'
            }
        }

        It 'sends model, state and a noul question for -Predicate' {
            Invoke-FoundryDecision -Model 'kev-0.8b' -State $state -Predicate @{ billing = 'About billing?' }
            Should -Invoke Invoke-FoundryApiRequest -ModuleName PwshFoundry -ParameterFilter {
                $Body.model -eq 'kev-0.8b' -and
                $Body.state.ticket -eq 'I was charged twice' -and
                $Body.questions['billing'].type -eq 'noul' -and
                $Body.questions['billing'].instructions -eq 'About billing?'
            }
        }

        It 'sends a choice question with its options as criteria' {
            Invoke-FoundryDecision -Model 'kev-0.8b' -State $state `
                -Choice @{ team = [ordered]@{ sales = 'Sales'; support = 'Support' } }
            Should -Invoke Invoke-FoundryApiRequest -ModuleName PwshFoundry -ParameterFilter {
                $Body.questions['team'].type -eq 'choice' -and
                $Body.questions['team'].criteria['support'] -eq 'Support'
            }
        }

        It 'sends a score question with its levels in order' {
            Invoke-FoundryDecision -Model 'kev-0.8b' -State $state -Score @{ priority = 'low', 'medium', 'high' }
            Should -Invoke Invoke-FoundryApiRequest -ModuleName PwshFoundry -ParameterFilter {
                $Body.questions['priority'].type -eq 'score' -and
                ($Body.questions['priority'].criteria -join ',') -eq 'low,medium,high'
            }
        }

        It 'keeps Predicate, Choice, Score, Question order' {
            Invoke-FoundryDecision -Model 'kev-0.8b' -State $state `
                -Question @{ raw = @{ type = 'noul'; instructions = 'x' } } `
                -Score @{ s = 'a', 'b' } `
                -Choice @{ c = @{ a = 'A'; b = 'B' } } `
                -Predicate @{ p = 'q' }
            Should -Invoke Invoke-FoundryApiRequest -ModuleName PwshFoundry -ParameterFilter {
                (@($Body.questions.Keys) -join ',') -eq 'p,c,s,raw'
            }
        }

        It 'produces the JSON keys the service parses' {
            Invoke-FoundryDecision -Model 'kev-0.8b' -State $state -Predicate @{ billing = 'About billing?' }
            Should -Invoke Invoke-FoundryApiRequest -ModuleName PwshFoundry -ParameterFilter {
                ($Body | ConvertTo-Json -Depth 10 -Compress) -eq
                    '{"model":"kev-0.8b","state":{"ticket":"I was charged twice"},' +
                    '"questions":{"billing":{"type":"noul","instructions":"About billing?"}}}'
            }
        }

        It 'omits temperature unless given' {
            Invoke-FoundryDecision -Model 'kev-0.8b' -State $state -Predicate @{ p = 'q' }
            Should -Invoke Invoke-FoundryApiRequest -ModuleName PwshFoundry -ParameterFilter {
                -not $Body.Contains('temperature')
            }
            Invoke-FoundryDecision -Model 'kev-0.8b' -State $state -Predicate @{ p = 'q' } -Temperature 1.0
            Should -Invoke Invoke-FoundryApiRequest -ModuleName PwshFoundry -ParameterFilter {
                $Body['temperature'] -eq 1.0
            }
        }

        It 'passes -Catalog Local and skips the catalog check' {
            Invoke-FoundryDecision -Model 'my-byom-model' -State $state -Predicate @{ p = 'q' } -Catalog Local
            Should -Invoke Invoke-FoundryApiRequest -ModuleName PwshFoundry -ParameterFilter { $Catalog -eq 'Local' }
            Should -Invoke Resolve-FoundryModel -ModuleName PwshFoundry -Times 0 -Exactly -Scope It
        }
    }

    Context 'Output' {
        It 'returns a PwshFoundry.Decision object' {
            $result = Invoke-FoundryDecision -Model 'kev-0.8b' -State $state -Predicate @{ billing = 'q' }
            $result.PSObject.TypeNames[0] | Should -Be 'PwshFoundry.Decision'
            $result.Model | Should -Be 'kev-0.8b-generic-gpu:1'
            $result.Answers.billing | Should -Be 0.97
            $result.Questions['billing'].type | Should -Be 'noul'
            $result.Usage.billing_units | Should -Be 0
        }

        It 'returns the raw response with -Raw' {
            $result = Invoke-FoundryDecision -Model 'kev-0.8b' -State $state -Predicate @{ billing = 'q' } -Raw
            $result.PSObject.TypeNames[0] | Should -Not -Be 'PwshFoundry.Decision'
            $result.answers.billing | Should -Be 0.97
        }
    }

    Context 'Validation' {
        It 'requires at least one question' {
            { Invoke-FoundryDecision -Model 'kev-0.8b' -State $state } |
                Should -Throw -ErrorId 'FoundryDecisionNoQuestion*'
        }

        It 'rejects a duplicate question id' {
            { Invoke-FoundryDecision -Model 'kev-0.8b' -State $state -Predicate @{ x = 'q' } -Score @{ x = 'a', 'b' } } |
                Should -Throw -ErrorId 'FoundryInvalidDecisionQuestion*'
        }

        It 'rejects a choice with fewer than two options' {
            { Invoke-FoundryDecision -Model 'kev-0.8b' -State $state -Choice @{ c = @{ a = 'A' } } } |
                Should -Throw -ExpectedMessage '*at least two option*'
        }

        It 'rejects a score with fewer than two levels' {
            { Invoke-FoundryDecision -Model 'kev-0.8b' -State $state -Score @{ s = @('only') } } |
                Should -Throw -ExpectedMessage '*at least two levels*'
        }

        It 'rejects an empty predicate' {
            { Invoke-FoundryDecision -Model 'kev-0.8b' -State $state -Predicate @{ p = ' ' } } |
                Should -Throw -ExpectedMessage '*non-empty instructions*'
        }

        It 'rejects a raw question without a type' {
            { Invoke-FoundryDecision -Model 'kev-0.8b' -State $state -Question @{ r = @{ instructions = 'x' } } } |
                Should -Throw -ExpectedMessage "*'type' entry*"
        }

        It 'rejects an unknown model' {
            Mock -ModuleName PwshFoundry Resolve-FoundryModel { }
            { Invoke-FoundryDecision -Model 'nope' -State $state -Predicate @{ p = 'q' } } |
                Should -Throw -ErrorId 'FoundryModelNotFound*'
        }

        It 'rejects a model that is not downloaded' {
            Mock -ModuleName PwshFoundry Resolve-FoundryModel {
                [PSCustomObject]@{ alias = 'kev-4b'; id = 'kev-4b-generic-gpu:1'; cached = $false }
            }
            { Invoke-FoundryDecision -Model 'kev-4b' -State $state -Predicate @{ p = 'q' } } |
                Should -Throw -ErrorId 'FoundryModelNotCached*'
        }

        It 'surfaces service errors as terminating errors' {
            Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest { throw 'HTTP 400 - expected typed-decision' }
            { Invoke-FoundryDecision -Model 'kev-0.8b' -State $state -Predicate @{ p = 'q' } } |
                Should -Throw -ExpectedMessage '*typed-decision*'
        }
    }
}
