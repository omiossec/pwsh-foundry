#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot/../src/PwshFoundry/PwshFoundry.psd1" -Force

    function script:Set-DefaultMock {
        param(
            [string[]] $LoadedModels = @(),
            [object] $CliResult = [PSCustomObject]@{
                success = $true
                message = "Downloaded 'openai-whisper-tiny-generic-cpu:4' to the local cache."
            }
        )

        Mock -ModuleName PwshFoundry Get-FoundryModelList {
            [PSCustomObject]@{
                alias = 'whisper-tiny'; id = 'openai-whisper-tiny-generic-cpu:4'; fileSizeMb = 131; cached = $true
            }
            [PSCustomObject]@{
                alias = 'qwen2.5-0.5b'; id = 'qwen2.5-0.5b-instruct-generic-cpu:4'; fileSizeMb = 822; cached = $false
            }
        }
        $script:cliResult = $CliResult
        Mock -ModuleName PwshFoundry Invoke-FoundryCli {
            $script:capturedArguments = $Arguments
            $script:cliResult
        }
        $script:loadedModels = $LoadedModels
        Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest -ParameterFilter { $Action -eq 'models-loaded' } {
            , $script:loadedModels
        }
        Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest -ParameterFilter { $Action -eq 'model-load' } {
            [PSCustomObject]@{ status = 'loaded' }
        }
        Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest -ParameterFilter { $Action -eq 'model-unload' } {
            [PSCustomObject]@{ status = 'unloaded' }
        }
    }
}

Describe 'Save-FoundryModel' {

    Context 'Download through the CLI' {
        BeforeEach {
            Set-DefaultMock
        }

        It 'runs foundry model download with the given name' {
            Save-FoundryModel -ModelID 'whisper-tiny'
            Should -Invoke Invoke-FoundryCli -ModuleName PwshFoundry -Times 1 -ParameterFilter {
                ($Arguments -join ' ') -eq 'model download whisper-tiny' -and $Json
            }
        }

        It 'adds --force with -Force' {
            Save-FoundryModel -ModelID 'whisper-tiny' -Force -Confirm:$false
            $script:capturedArguments | Should -Contain '--force'
        }

        It 'does not add --force by default' {
            Save-FoundryModel -ModelID 'whisper-tiny'
            $script:capturedArguments | Should -Not -Contain '--force'
        }

        It 'does not call the service when -Load is not used' {
            Save-FoundryModel -ModelID 'whisper-tiny'
            Should -Invoke Invoke-FoundryApiRequest -ModuleName PwshFoundry -Times 0
        }

        It 'accepts an alias, an id and a versioned id' -ForEach @(
            'whisper-tiny', 'openai-whisper-tiny-generic-cpu', 'openai-whisper-tiny-generic-cpu:4'
        ) {
            { Save-FoundryModel -ModelID $_ } | Should -Not -Throw
        }

        It 'does nothing with -WhatIf' {
            Save-FoundryModel -ModelID 'whisper-tiny' -WhatIf
            Should -Invoke Invoke-FoundryCli -ModuleName PwshFoundry -Times 0
        }
    }

    Context 'Output' {
        It 'reports a fresh download' {
            Set-DefaultMock
            $result = Save-FoundryModel -ModelID 'whisper-tiny'
            $result.Alias | Should -Be 'whisper-tiny'
            $result.Id | Should -Be 'openai-whisper-tiny-generic-cpu:4'
            $result.Downloaded | Should -BeTrue
            $result.Loaded | Should -BeFalse
            $result.Message | Should -BeLike 'Downloaded*'
        }

        It 'reports an already cached model' {
            Set-DefaultMock -CliResult ([PSCustomObject]@{
                success = $true
                info    = "Model 'openai-whisper-tiny-generic-cpu:4' is already cached. Use --force to download it again."
            })
            $result = Save-FoundryModel -ModelID 'whisper-tiny'
            $result.Downloaded | Should -BeFalse
            $result.Message | Should -BeLike '*already cached*'
        }

        It 'refreshes the catalog after the download' {
            Set-DefaultMock
            Save-FoundryModel -ModelID 'whisper-tiny'
            Should -Invoke Get-FoundryModelList -ModuleName PwshFoundry -ParameterFilter { $ByPassCache }
        }
    }

    Context 'Loading' {
        It 'loads the model by alias with -Load' {
            Set-DefaultMock
            $result = Save-FoundryModel -ModelID 'openai-whisper-tiny-generic-cpu:4' -Load
            Should -Invoke Invoke-FoundryApiRequest -ModuleName PwshFoundry -Times 1 -ParameterFilter {
                $Action -eq 'model-load' -and $PathParameters.name -eq 'whisper-tiny'
            }
            $result.Loaded | Should -BeTrue
        }

        It 'passes -Port to the service' {
            Set-DefaultMock
            Save-FoundryModel -ModelID 'whisper-tiny' -Load -Port 5273
            Should -Invoke Invoke-FoundryApiRequest -ModuleName PwshFoundry -ParameterFilter {
                $Action -eq 'model-load' -and $Port -eq 5273
            }
        }
    }

    Context '-Force on a loaded model' {
        It 'unloads it before the download and loads it again afterwards' {
            Set-DefaultMock -LoadedModels @('openai-whisper-tiny-generic-cpu:4')
            $result = Save-FoundryModel -ModelID 'whisper-tiny' -Force -Confirm:$false
            Should -Invoke Invoke-FoundryApiRequest -ModuleName PwshFoundry -Times 1 -ParameterFilter {
                $Action -eq 'model-unload' -and $PathParameters.name -eq 'whisper-tiny'
            }
            Should -Invoke Invoke-FoundryApiRequest -ModuleName PwshFoundry -Times 1 -ParameterFilter {
                $Action -eq 'model-load' -and $PathParameters.name -eq 'whisper-tiny'
            }
            $result.Loaded | Should -BeTrue
        }

        It 'does not unload when the model is not loaded' {
            Set-DefaultMock -LoadedModels @('qwen2.5-0.5b-instruct-generic-cpu:4')
            Save-FoundryModel -ModelID 'whisper-tiny' -Force -Confirm:$false
            Should -Invoke Invoke-FoundryApiRequest -ModuleName PwshFoundry -Times 0 -ParameterFilter {
                $Action -in 'model-unload', 'model-load'
            }
        }

        It 'still downloads when the service is not running' {
            Set-DefaultMock
            Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest -ParameterFilter { $Action -eq 'models-loaded' } {
                throw 'connection refused'
            }
            { Save-FoundryModel -ModelID 'whisper-tiny' -Force -Confirm:$false } | Should -Not -Throw
            Should -Invoke Invoke-FoundryCli -ModuleName PwshFoundry -Times 1
        }
    }

    Context 'Errors' {
        BeforeEach {
            Set-DefaultMock
        }

        It 'throws when the model is not in the catalog' {
            { Save-FoundryModel -ModelID 'no-such-model' } |
                Should -Throw -ErrorId 'FoundryModelNotFound,Save-FoundryModel'
            Should -Invoke Invoke-FoundryCli -ModuleName PwshFoundry -Times 0
        }

        It 'throws when the CLI reports a failure' {
            Set-DefaultMock -CliResult ([PSCustomObject]@{ success = $false; message = 'disk full' })
            { Save-FoundryModel -ModelID 'whisper-tiny' } |
                Should -Throw -ErrorId 'FoundryModelDownloadFailed,Save-FoundryModel'
        }

        It 'throws for a Port out of range' {
            { Save-FoundryModel -ModelID 'whisper-tiny' -Port 70000 } | Should -Throw
        }
    }
}
