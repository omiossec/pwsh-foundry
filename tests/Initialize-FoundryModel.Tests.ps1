#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot/../src/PwshFoundry/PwshFoundry.psd1" -Force
}

Describe 'Initialize-FoundryModel' {

    BeforeEach {
        Mock -ModuleName PwshFoundry Get-FoundryModelList {
            [PSCustomObject]@{ alias = 'qwen3-0.6b'; id = 'qwen3-0.6b-generic-gpu:1'; cached = $true }
            [PSCustomObject]@{ alias = 'qwen3-0.6b'; id = 'qwen3-0.6b-generic-cpu:1'; cached = $true }
        }
        Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest { } -ParameterFilter { $Action -eq 'model-load' }
        $script:loaded = @()
        Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest { $script:loaded } -ParameterFilter {
            $Action -eq 'models-loaded'
        }
    }

    It 'returns nothing for a model that is not in the catalog' {
        InModuleScope PwshFoundry { Initialize-FoundryModel -Name 'no-such-model' } | Should -BeNullOrEmpty
        Should -Invoke Invoke-FoundryApiRequest -ModuleName PwshFoundry -Times 0 -ParameterFilter {
            $Action -eq 'model-load'
        }
    }

    It 'returns the versioned id without loading when the model is already loaded' {
        $script:loaded = @('qwen3-0.6b-generic-cpu:1')
        InModuleScope PwshFoundry { Initialize-FoundryModel -Name 'qwen3-0.6b-generic-cpu' } |
            Should -Be 'qwen3-0.6b-generic-cpu:1'
        Should -Invoke Invoke-FoundryApiRequest -ModuleName PwshFoundry -Times 0 -ParameterFilter {
            $Action -eq 'model-load'
        }
    }

    It 'loads the model by alias when an id is given' {
        Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest { $script:loaded = @('qwen3-0.6b-generic-gpu:1') } `
            -ParameterFilter { $Action -eq 'model-load' }
        InModuleScope PwshFoundry { Initialize-FoundryModel -Name 'qwen3-0.6b-generic-gpu' } |
            Should -Be 'qwen3-0.6b-generic-gpu:1'
        Should -Invoke Invoke-FoundryApiRequest -ModuleName PwshFoundry -Times 1 -ParameterFilter {
            $Action -eq 'model-load' -and $PathParameters.name -eq 'qwen3-0.6b'
        }
    }

    It 'throws a FoundryModelNotCached error when the model is not downloaded' {
        Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest {
            throw 'Foundry API request failed: 400. Model not cached: Model must be downloaded before loading'
        } -ParameterFilter { $Action -eq 'model-load' }
        { InModuleScope PwshFoundry { Initialize-FoundryModel -Name 'qwen3-0.6b-generic-gpu' } } |
            Should -Throw -ErrorId 'FoundryModelNotCached*'
    }

    It 'returns the variant Foundry loaded when an alias is given' {
        Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest { $script:loaded = @('qwen3-0.6b-generic-cpu:1') } `
            -ParameterFilter { $Action -eq 'model-load' }
        InModuleScope PwshFoundry { Initialize-FoundryModel -Name 'qwen3-0.6b' } |
            Should -Be 'qwen3-0.6b-generic-cpu:1'
    }

    It 'warns when Foundry loads another variant than the requested id' {
        Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest { $script:loaded = @('qwen3-0.6b-generic-cpu:1') } `
            -ParameterFilter { $Action -eq 'model-load' }
        $result = InModuleScope PwshFoundry {
            Initialize-FoundryModel -Name 'qwen3-0.6b-generic-gpu' -WarningVariable w -WarningAction SilentlyContinue
            $w.Count
        }
        $result[0] | Should -Be 'qwen3-0.6b-generic-cpu:1'
        $result[1] | Should -Be 1
    }
}
