#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot/../src/PwshFoundry/PwshFoundry.psd1" -Force
}

Describe 'New-FoundryAudioTranscription' {

    Context 'Correct API call' {
        BeforeAll {
            $script:audioFile = Join-Path $TestDrive 'test.mp3'
            New-Item -Path $script:audioFile -ItemType File -Force | Out-Null
            Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest { [PSCustomObject]@{ text = 'Hello world' } }
        }

        It 'calls /v1/audio/transcriptions with POST' {
            New-FoundryAudioTranscription -ModelId 'whisper-1' -AudioFile $script:audioFile
            Should -Invoke Invoke-FoundryApiRequest -ModuleName PwshFoundry -ParameterFilter {
                $Path -eq '/v1/audio/transcriptions' -and $Method -eq 'POST'
            }
        }

        It 'returns the API response' {
            $result = New-FoundryAudioTranscription -ModelId 'whisper-1' -AudioFile $script:audioFile
            $result.text | Should -Be 'Hello world'
        }
    }

    Context 'Body composition - required fields' {
        BeforeAll {
            $script:audioFile = Join-Path $TestDrive 'recording.wav'
            New-Item -Path $script:audioFile -ItemType File -Force | Out-Null
            Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest {
                $script:capturedBody = $Body
                [PSCustomObject]@{}
            }
            New-FoundryAudioTranscription -ModelId 'whisper-1' -AudioFile $script:audioFile
        }

        It 'includes model' {
            $script:capturedBody['model'] | Should -Be 'whisper-1'
        }

        It 'includes the resolved file path' {
            $script:capturedBody['file'] | Should -Be (Resolve-Path $script:audioFile).Path
        }

        It 'defaults language to en' {
            $script:capturedBody['language'] | Should -Be 'en'
        }

        It 'defaults response_format to text' {
            $script:capturedBody['response_format'] | Should -Be 'text'
        }

        It 'omits temperature when not supplied' {
            $script:capturedBody.ContainsKey('temperature') | Should -BeFalse
        }
    }

    Context 'Optional parameters are included when supplied' {
        BeforeAll {
            $script:audioFile = Join-Path $TestDrive 'audio.flac'
            New-Item -Path $script:audioFile -ItemType File -Force | Out-Null
            Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest {
                $script:capturedBody = $Body
                [PSCustomObject]@{}
            }
        }

        It 'includes language when supplied' {
            New-FoundryAudioTranscription -ModelId 'whisper-1' -AudioFile $script:audioFile -Language 'fr'
            $script:capturedBody['language'] | Should -Be 'fr'
        }

        It 'includes temperature when supplied' {
            New-FoundryAudioTranscription -ModelId 'whisper-1' -AudioFile $script:audioFile -Temperature 0.5
            $script:capturedBody.ContainsKey('temperature') | Should -BeTrue
            $script:capturedBody['temperature']             | Should -Be 0.5
        }

        It 'includes response_format when supplied' {
            New-FoundryAudioTranscription -ModelId 'whisper-1' -AudioFile $script:audioFile -ResponseFormat 'json'
            $script:capturedBody['response_format'] | Should -Be 'json'
        }
    }

    Context 'Parameter validation - ModelId must contain whisper' {
        BeforeAll {
            $script:audioFile = Join-Path $TestDrive 'model-check.mp3'
            New-Item -Path $script:audioFile -ItemType File -Force | Out-Null
            Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest { [PSCustomObject]@{} }
        }

        It 'accepts a model name with whisper (lowercase)' {
            { New-FoundryAudioTranscription -ModelId 'whisper-large-v3' -AudioFile $script:audioFile } | Should -Not -Throw
        }

        It 'accepts a model name with Whisper (mixed case)' {
            { New-FoundryAudioTranscription -ModelId 'Whisper-1' -AudioFile $script:audioFile } | Should -Not -Throw
        }

        It 'throws when model does not contain whisper' {
            { New-FoundryAudioTranscription -ModelId 'phi-3-mini' -AudioFile $script:audioFile } | Should -Throw
        }
    }

    Context 'Parameter validation - AudioFile extension' {
        BeforeAll {
            Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest { [PSCustomObject]@{} }
        }

        It 'accepts .mp3' {
            $f = Join-Path $TestDrive 'a.mp3'
            New-Item $f -ItemType File -Force | Out-Null
            { New-FoundryAudioTranscription -ModelId 'whisper-1' -AudioFile $f } | Should -Not -Throw
        }

        It 'accepts .wav' {
            $f = Join-Path $TestDrive 'a.wav'
            New-Item $f -ItemType File -Force | Out-Null
            { New-FoundryAudioTranscription -ModelId 'whisper-1' -AudioFile $f } | Should -Not -Throw
        }

        It 'accepts .flac' {
            $f = Join-Path $TestDrive 'a.flac'
            New-Item $f -ItemType File -Force | Out-Null
            { New-FoundryAudioTranscription -ModelId 'whisper-1' -AudioFile $f } | Should -Not -Throw
        }

        It 'accepts .ogg' {
            $f = Join-Path $TestDrive 'a.ogg'
            New-Item $f -ItemType File -Force | Out-Null
            { New-FoundryAudioTranscription -ModelId 'whisper-1' -AudioFile $f } | Should -Not -Throw
        }

        It 'accepts .webm' {
            $f = Join-Path $TestDrive 'a.webm'
            New-Item $f -ItemType File -Force | Out-Null
            { New-FoundryAudioTranscription -ModelId 'whisper-1' -AudioFile $f } | Should -Not -Throw
        }

        It 'throws for .txt extension' {
            { New-FoundryAudioTranscription -ModelId 'whisper-1' -AudioFile (Join-Path $TestDrive 'a.txt') } | Should -Throw
        }

        It 'throws for .mp4 extension' {
            { New-FoundryAudioTranscription -ModelId 'whisper-1' -AudioFile (Join-Path $TestDrive 'a.mp4') } | Should -Throw
        }
    }

    Context 'Parameter validation - AudioFile must exist on disk' {
        It 'throws when the file does not exist' {
            { New-FoundryAudioTranscription -ModelId 'whisper-1' -AudioFile (Join-Path $TestDrive 'nonexistent.mp3') } | Should -Throw
        }
    }

    Context 'Parameter validation - Temperature range' {
        BeforeAll {
            $script:audioFile = Join-Path $TestDrive 'temp-range.mp3'
            New-Item -Path $script:audioFile -ItemType File -Force | Out-Null
            Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest { [PSCustomObject]@{} }
        }

        It 'accepts boundary value 0.0' {
            { New-FoundryAudioTranscription -ModelId 'whisper-1' -AudioFile $script:audioFile -Temperature 0.0 } | Should -Not -Throw
        }

        It 'accepts boundary value 1.0' {
            { New-FoundryAudioTranscription -ModelId 'whisper-1' -AudioFile $script:audioFile -Temperature 1.0 } | Should -Not -Throw
        }

        It 'throws when Temperature is below 0' {
            { New-FoundryAudioTranscription -ModelId 'whisper-1' -AudioFile $script:audioFile -Temperature -0.1 } | Should -Throw
        }

        It 'throws when Temperature is above 1' {
            { New-FoundryAudioTranscription -ModelId 'whisper-1' -AudioFile $script:audioFile -Temperature 1.1 } | Should -Throw
        }
    }

    Context 'Parameter validation - ResponseFormat' {
        BeforeAll {
            $script:audioFile = Join-Path $TestDrive 'fmt.mp3'
            New-Item -Path $script:audioFile -ItemType File -Force | Out-Null
            Mock -ModuleName PwshFoundry Invoke-FoundryApiRequest { [PSCustomObject]@{} }
        }

        It 'accepts text' {
            { New-FoundryAudioTranscription -ModelId 'whisper-1' -AudioFile $script:audioFile -ResponseFormat 'text' } | Should -Not -Throw
        }

        It 'accepts json' {
            { New-FoundryAudioTranscription -ModelId 'whisper-1' -AudioFile $script:audioFile -ResponseFormat 'json' } | Should -Not -Throw
        }

        It 'accepts verbose_json' {
            { New-FoundryAudioTranscription -ModelId 'whisper-1' -AudioFile $script:audioFile -ResponseFormat 'verbose_json' } | Should -Not -Throw
        }

        It 'throws for an invalid format value' {
            { New-FoundryAudioTranscription -ModelId 'whisper-1' -AudioFile $script:audioFile -ResponseFormat 'xml' } | Should -Throw
        }
    }

    Context 'Mandatory parameters' {
        It 'throws when ModelId is not provided' {
            { New-FoundryAudioTranscription -AudioFile (Join-Path $TestDrive 'a.mp3') } | Should -Throw
        }

        It 'throws when AudioFile is not provided' {
            { New-FoundryAudioTranscription -ModelId 'whisper-1' } | Should -Throw
        }
    }
}
