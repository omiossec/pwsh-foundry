#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot/../src/PwshFoundry/PwshFoundry.psd1" -Force
}

Describe 'Compare-FoundryEmbedding' {

    It 'returns 1 for identical vectors' {
        Compare-FoundryEmbedding -ReferenceEmbedding @(1.0, 2.0, 3.0) -DifferenceEmbedding @(1.0, 2.0, 3.0) |
            Should -Be 1
    }

    It 'returns 0 for orthogonal vectors' {
        Compare-FoundryEmbedding -ReferenceEmbedding @(1.0, 0.0) -DifferenceEmbedding @(0.0, 1.0) |
            Should -Be 0
    }

    It 'returns -1 for opposite vectors' {
        Compare-FoundryEmbedding -ReferenceEmbedding @(1.0, 0.0) -DifferenceEmbedding @(-1.0, 0.0) |
            Should -Be -1
    }

    It 'is invariant to vector magnitude' {
        Compare-FoundryEmbedding -ReferenceEmbedding @(1.0, 1.0) -DifferenceEmbedding @(10.0, 10.0) |
            Should -BeGreaterThan 0.9999
    }

    It 'returns 0 when one vector is all zeros' {
        Compare-FoundryEmbedding -ReferenceEmbedding @(0.0, 0.0) -DifferenceEmbedding @(1.0, 1.0) |
            Should -Be 0
    }

    It 'throws FoundryEmbeddingLengthMismatch for vectors of different length' {
        { Compare-FoundryEmbedding -ReferenceEmbedding @(1.0, 2.0) -DifferenceEmbedding @(1.0) -ErrorAction Stop } |
            Should -Throw -ErrorId 'FoundryEmbeddingLengthMismatch,Compare-FoundryEmbedding'
    }

    It 'accepts New-FoundryEmbedding result objects' {
        $a = [PSCustomObject]@{ Index = 0; Text = 'a'; Embedding = [double[]]@(1.0, 0.0) }
        $b = [PSCustomObject]@{ Index = 1; Text = 'b'; Embedding = [double[]]@(1.0, 0.0) }
        Compare-FoundryEmbedding -ReferenceEmbedding $a -DifferenceEmbedding $b | Should -Be 1
    }

    It 'accepts a mix of result object and raw vector' {
        $a = [PSCustomObject]@{ Index = 0; Text = 'a'; Embedding = [double[]]@(0.0, 1.0) }
        Compare-FoundryEmbedding -ReferenceEmbedding $a -DifferenceEmbedding @(1.0, 0.0) | Should -Be 0
    }
}
