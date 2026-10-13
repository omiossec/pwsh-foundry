#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot/../src/PwshFoundry/PwshFoundry.psd1" -Force

    # Shared mocks: Foundry 0.11.0, a whisper model in the catalog, model already loaded.
    function script:Set-DefaultMock {
        param([string[]] $LoadedModels = @('openai-whisper-small-generic-cpu:4'))

        Mock -ModuleName PwshFoundry Get-FoundryVersion {
            [PSCustomObject]@{ Source = 'CLI'; Version = '0.11.0'; Message = '0.11.0' }
        }
        Mock -ModuleName PwshFoundry Get-FoundryModelList {
            [PSCustomObject]@{ alias = 'whisper-small'; id = 'openai-whisper-small-generic-cpu:4' }
            [PSCustomObject]@{ alias = 'qwen2.5-0.5b'; id = 'qwen2.5-0.5b-instruct-generic-cpu:4' }
        }
        Mock -ModuleName PwshFoundry New-FoundryLogEntries { }
        $script:loadedModels = $LoadedModels
        Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest -ParameterFilter { $Action -eq 'models-loaded' } {
            , $script:loadedModels
        }
        Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest -ParameterFilter { $Action -eq 'model-load' } {
            $script:loadedModels = @('openai-whisper-small-generic-cpu:4')
            'ok'
        }
        Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest -ParameterFilter { $Action -eq 'transcribe' } {
            $script:capturedBody = $Body
            [PSCustomObject]@{ id = 'audio_123'; text = ' Hello world' }
        }
    }
}

Describe 'New-FoundryAudioTranscription' {

    Context 'REST API call' {
        BeforeAll {
            $script:audioFile = Join-Path $TestDrive 'test.mp3'
            New-Item -Path $script:audioFile -ItemType File -Force | Out-Null
            Set-DefaultMock
        }

        It 'POSTs to the transcribe action' {
            New-FoundryAudioTranscription -ModelId 'whisper-small' -AudioFile $script:audioFile
            Should -Invoke Invoke-FoundryApiRequest -ModuleName PwshFoundry -ParameterFilter {
                $Action -eq 'transcribe' -and $Method -eq 'POST'
            }
        }

        It 'returns the trimmed text by default' {
            $result = New-FoundryAudioTranscription -ModelId 'whisper-small' -AudioFile $script:audioFile
            $result | Should -Be 'Hello world'
        }

        It 'returns an object when ResponseFormat is json' {
            $result = New-FoundryAudioTranscription -ModelId 'whisper-small' -AudioFile $script:audioFile -ResponseFormat 'json'
            $result.Id | Should -Be 'audio_123'
            $result.Text | Should -Be 'Hello world'
            $result.Model | Should -Be 'openai-whisper-small-generic-cpu:4'
            $result.AudioFile | Should -Be (Resolve-Path $script:audioFile).ProviderPath
        }

        It 'does not call the Foundry CLI' {
            Mock -ModuleName PwshFoundry Invoke-FoundryCli { }
            New-FoundryAudioTranscription -ModelId 'whisper-small' -AudioFile $script:audioFile
            Should -Invoke Invoke-FoundryCli -ModuleName PwshFoundry -Times 0
        }
    }

    Context 'Request body composition' {
        BeforeAll {
            $script:audioFile = Join-Path $TestDrive 'recording.wav'
            New-Item -Path $script:audioFile -ItemType File -Force | Out-Null
            Set-DefaultMock
        }

        It 'sends the versioned model id when given an alias' {
            New-FoundryAudioTranscription -ModelId 'whisper-small' -AudioFile $script:audioFile
            $script:capturedBody.model | Should -Be 'openai-whisper-small-generic-cpu:4'
        }

        It 'sends the versioned model id when given an unversioned id' {
            New-FoundryAudioTranscription -ModelId 'openai-whisper-small-generic-cpu' -AudioFile $script:audioFile
            $script:capturedBody.model | Should -Be 'openai-whisper-small-generic-cpu:4'
        }

        It 'sends the resolved absolute path as filename' {
            New-FoundryAudioTranscription -ModelId 'whisper-small' -AudioFile $script:audioFile
            $script:capturedBody.filename | Should -Be (Resolve-Path $script:audioFile).ProviderPath
        }

        It 'omits optional fields when not supplied' {
            New-FoundryAudioTranscription -ModelId 'whisper-small' -AudioFile $script:audioFile
            $script:capturedBody.Keys | Should -Not -Contain 'language'
            $script:capturedBody.Keys | Should -Not -Contain 'prompt'
            $script:capturedBody.Keys | Should -Not -Contain 'temperature'
        }

        It 'includes language, prompt and temperature when supplied' {
            New-FoundryAudioTranscription -ModelId 'whisper-small' -AudioFile $script:audioFile `
                -Language 'FR' -Prompt 'meeting notes' -Temperature 0.2
            $script:capturedBody.language | Should -Be 'fr'
            $script:capturedBody.prompt | Should -Be 'meeting notes'
            $script:capturedBody.temperature | Should -Be 0.2
        }
    }

    Context 'Model loading' {
        BeforeAll {
            $script:audioFile = Join-Path $TestDrive 'load.mp3'
            New-Item -Path $script:audioFile -ItemType File -Force | Out-Null
        }

        It 'does not load the model when it is already loaded' {
            Set-DefaultMock
            New-FoundryAudioTranscription -ModelId 'whisper-small' -AudioFile $script:audioFile
            Should -Invoke Invoke-FoundryApiRequest -ModuleName PwshFoundry -Times 0 -ParameterFilter {
                $Action -eq 'model-load'
            }
        }

        It 'loads the model by alias when it is not loaded' {
            Set-DefaultMock -LoadedModels @()
            New-FoundryAudioTranscription -ModelId 'openai-whisper-small-generic-cpu:4' -AudioFile $script:audioFile
            Should -Invoke Invoke-FoundryApiRequest -ModuleName PwshFoundry -Times 1 -ParameterFilter {
                $Action -eq 'model-load' -and $PathParameters.name -eq 'whisper-small'
            }
            $script:capturedBody.model | Should -Be 'openai-whisper-small-generic-cpu:4'
        }

        It 'throws when the model is not in the catalog' {
            Set-DefaultMock
            { New-FoundryAudioTranscription -ModelId 'whisper-unknown' -AudioFile $script:audioFile } |
                Should -Throw -ExpectedMessage "*does not exist in the local Foundry*"
        }
    }

    Context 'Foundry version' {
        BeforeAll {
            $script:audioFile = Join-Path $TestDrive 'version.mp3'
            New-Item -Path $script:audioFile -ItemType File -Force | Out-Null
            Set-DefaultMock
        }

        It 'throws on Foundry CLI older than 0.11.0' {
            Mock -ModuleName PwshFoundry Get-FoundryVersion {
                [PSCustomObject]@{ Source = 'CLI'; Version = '0.10.2'; Message = '0.10.2' }
            }
            { New-FoundryAudioTranscription -ModelId 'whisper-small' -AudioFile $script:audioFile } |
                Should -Throw -ExpectedMessage '*requires Foundry Local 0.11.0*'
        }

        It 'accepts SDK mode' {
            Mock -ModuleName PwshFoundry Get-FoundryVersion {
                [PSCustomObject]@{ Source = 'SDK'; Version = $null; Message = 'SDK' }
            }
            { New-FoundryAudioTranscription -ModelId 'whisper-small' -AudioFile $script:audioFile } |
                Should -Not -Throw
        }
    }

    Context 'Parameter validation - ModelId must contain whisper' {
        BeforeAll {
            $script:audioFile = Join-Path $TestDrive 'model-check.mp3'
            New-Item -Path $script:audioFile -ItemType File -Force | Out-Null
            Set-DefaultMock
        }

        It 'accepts a model name with Whisper (mixed case)' {
            { New-FoundryAudioTranscription -ModelId 'Whisper-Small' -AudioFile $script:audioFile } |
                Should -Not -Throw
        }

        It 'throws when model does not contain whisper' {
            { New-FoundryAudioTranscription -ModelId 'qwen2.5-0.5b' -AudioFile $script:audioFile } |
                Should -Throw -ErrorId 'ParameterArgumentValidationError,New-FoundryAudioTranscription'
        }
    }

    Context 'Parameter validation - AudioFile extension' {
        BeforeAll {
            Set-DefaultMock
        }

        It 'accepts .<_>' -ForEach @('mp3', 'wav', 'flac', 'ogg', 'webm') {
            $f = Join-Path $TestDrive "a.$_"
            New-Item $f -ItemType File -Force | Out-Null
            { New-FoundryAudioTranscription -ModelId 'whisper-small' -AudioFile $f } | Should -Not -Throw
        }

        It 'throws for .<_> extension' -ForEach @('txt', 'mp4') {
            { New-FoundryAudioTranscription -ModelId 'whisper-small' -AudioFile (Join-Path $TestDrive "a.$_") } |
                Should -Throw
        }
    }

    Context 'Parameter validation - other parameters' {
        BeforeAll {
            $script:audioFile = Join-Path $TestDrive 'fmt.mp3'
            New-Item -Path $script:audioFile -ItemType File -Force | Out-Null
            Set-DefaultMock
        }

        It 'throws when the file does not exist' {
            { New-FoundryAudioTranscription -ModelId 'whisper-small' -AudioFile (Join-Path $TestDrive 'nonexistent.mp3') } |
                Should -Throw -ErrorId 'AudioFileNotFound,New-FoundryAudioTranscription'
        }

        It 'throws for an invalid ResponseFormat value' {
            { New-FoundryAudioTranscription -ModelId 'whisper-small' -AudioFile $script:audioFile -ResponseFormat 'xml' } |
                Should -Throw
        }

        It 'throws for a Temperature above 1' {
            { New-FoundryAudioTranscription -ModelId 'whisper-small' -AudioFile $script:audioFile -Temperature 1.5 } |
                Should -Throw
        }

        It 'throws for an invalid Language code' {
            { New-FoundryAudioTranscription -ModelId 'whisper-small' -AudioFile $script:audioFile -Language 'english' } |
                Should -Throw
        }
    }

    Context 'Mandatory parameters' {
        It 'throws when ModelId is not provided' {
            { New-FoundryAudioTranscription -AudioFile (Join-Path $TestDrive 'a.mp3') } | Should -Throw
        }

        It 'throws when AudioFile is not provided' {
            { New-FoundryAudioTranscription -ModelId 'whisper-small' } | Should -Throw
        }
    }
}
