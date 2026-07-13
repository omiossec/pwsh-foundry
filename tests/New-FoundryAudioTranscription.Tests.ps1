#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot/../src/PwshFoundry/PwshFoundry.psd1" -Force
}

Describe 'New-FoundryAudioTranscription' {

    Context 'Correct CLI call' {
        BeforeAll {
            $script:audioFile = Join-Path $TestDrive 'test.mp3'
            New-Item -Path $script:audioFile -ItemType File -Force | Out-Null
            Mock -ModuleName PwshFoundry Invoke-FoundryCli { 'Hello world' }
        }

        It 'calls the transcribe subcommand' {
            New-FoundryAudioTranscription -ModelId 'whisper-1' -AudioFile $script:audioFile
            Should -Invoke Invoke-FoundryCli -ModuleName PwshFoundry -ParameterFilter {
                $Arguments[0] -eq 'transcribe'
            }
        }

        It 'returns the CLI response' {
            $result = New-FoundryAudioTranscription -ModelId 'whisper-1' -AudioFile $script:audioFile
            $result | Should -Be 'Hello world'
        }
    }

    Context 'Argument composition - required fields' {
        BeforeAll {
            $script:audioFile = Join-Path $TestDrive 'recording.wav'
            New-Item -Path $script:audioFile -ItemType File -Force | Out-Null
            Mock -ModuleName PwshFoundry Invoke-FoundryCli {
                $script:capturedArguments = $Arguments
                'ok'
            }
            New-FoundryAudioTranscription -ModelId 'whisper-1' -AudioFile $script:audioFile
        }

        It 'includes --model' {
            $index = $script:capturedArguments.IndexOf('--model')
            $script:capturedArguments[$index + 1] | Should -Be 'whisper-1'
        }

        It 'includes the resolved file path with --file' {
            $index = $script:capturedArguments.IndexOf('--file')
            $script:capturedArguments[$index + 1] | Should -Be (Resolve-Path $script:audioFile).Path
        }

        It 'defaults --language to en' {
            $index = $script:capturedArguments.IndexOf('--language')
            $script:capturedArguments[$index + 1] | Should -Be 'en'
        }

        It 'defaults --output to text' {
            $index = $script:capturedArguments.IndexOf('--output')
            $script:capturedArguments[$index + 1] | Should -Be 'text'
        }
    }

    Context 'Optional parameters are included when supplied' {
        BeforeAll {
            $script:audioFile = Join-Path $TestDrive 'audio.flac'
            New-Item -Path $script:audioFile -ItemType File -Force | Out-Null
            Mock -ModuleName PwshFoundry Invoke-FoundryCli {
                $script:capturedArguments = $Arguments
                'ok'
            }
        }

        It 'includes language when supplied' {
            New-FoundryAudioTranscription -ModelId 'whisper-1' -AudioFile $script:audioFile -Language 'fr'
            $index = $script:capturedArguments.IndexOf('--language')
            $script:capturedArguments[$index + 1] | Should -Be 'fr'
        }

        It 'includes response format when supplied' {
            New-FoundryAudioTranscription -ModelId 'whisper-1' -AudioFile $script:audioFile -ResponseFormat 'json'
            $index = $script:capturedArguments.IndexOf('--output')
            $script:capturedArguments[$index + 1] | Should -Be 'json'
        }
    }

    Context 'Parameter validation - ModelId must contain whisper' {
        BeforeAll {
            $script:audioFile = Join-Path $TestDrive 'model-check.mp3'
            New-Item -Path $script:audioFile -ItemType File -Force | Out-Null
            Mock -ModuleName PwshFoundry Invoke-FoundryCli { 'ok' }
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
            Mock -ModuleName PwshFoundry Invoke-FoundryCli { 'ok' }
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

    Context 'Parameter validation - ResponseFormat' {
        BeforeAll {
            $script:audioFile = Join-Path $TestDrive 'fmt.mp3'
            New-Item -Path $script:audioFile -ItemType File -Force | Out-Null
            Mock -ModuleName PwshFoundry Invoke-FoundryCli { 'ok' }
        }

        It 'accepts text' {
            { New-FoundryAudioTranscription -ModelId 'whisper-1' -AudioFile $script:audioFile -ResponseFormat 'text' } | Should -Not -Throw
        }

        It 'accepts json' {
            { New-FoundryAudioTranscription -ModelId 'whisper-1' -AudioFile $script:audioFile -ResponseFormat 'json' } | Should -Not -Throw
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
