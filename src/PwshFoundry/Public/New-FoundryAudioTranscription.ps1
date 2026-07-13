#Requires -Version 7.0

function New-FoundryAudioTranscription {
    <#
    .SYNOPSIS
        Transcribes an audio file to text using a local Foundry speech model.
    .DESCRIPTION
        Runs `foundry transcribe` via the Foundry CLI and returns the transcription result.
    .EXAMPLE
        New-FoundryAudioTranscription -ModelId 'whisper-1' -AudioFile 'C:\recordings\meeting.mp3'
    .EXAMPLE
        New-FoundryAudioTranscription -ModelId 'whisper-large-v3' -AudioFile './interview.wav' -Language 'fr' -ResponseFormat 'json'
    .PARAMETER LogFilePath
        Optional path to a log file. When specified, the request and the transcription
        result are appended to this file via New-FoundryLogEntries. When omitted,
        New-FoundryLogEntries logs to its default location.
    .NOTES
        This function shells out to `foundry transcribe`; the local audio transcriptions
        REST endpoint is not used.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('(?i)whisper')]
        [string] $ModelId,

        [Parameter(Mandatory)]
        [ValidatePattern('(?i)\.(mp3|wav|flac|ogg|webm)$')]
        [string] $AudioFile,

        [Parameter()]
        [string] $Language = 'en',

        [Parameter()]
        [ValidateSet('text', 'json')]
        [string] $ResponseFormat = 'text',

        [Parameter()]
        [string] $LogFilePath
    )

    if (-not (Test-Path -Path $AudioFile -PathType Leaf)) {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.IO.FileNotFoundException]::new("Audio file not found: '$AudioFile'"),
                'AudioFileNotFound',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                $AudioFile
            )
        )
    }

    if ($PSBoundParameters.ContainsKey('LogFilePath') -and -not (Test-FoundryLogFilePath -Path $LogFilePath)) {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.ArgumentException]::new(
                    "LogFilePath '$LogFilePath' is not valid, or its parent directory does not exist."
                ),
                'FoundryInvalidLogFilePath',
                [System.Management.Automation.ErrorCategory]::InvalidArgument,
                $LogFilePath
            )
        )
    }

    $resolvedAudioFile = (Resolve-Path -Path $AudioFile).Path

    $arguments = @(
        'transcribe'
        '--model', $ModelId
        '--language', $Language
        '--file', $resolvedAudioFile
        '--output', $ResponseFormat
    )

    Write-Verbose "Invoking: foundry $($arguments -join ' ')"

    $isJson = $ResponseFormat -eq 'json'
    if ($isJson) {
        $transcription = Invoke-FoundryCli -Arguments $arguments -Json
    } else {
        $transcription = (Invoke-FoundryCli -Arguments $arguments) -join [System.Environment]::NewLine
    }

    $assistantPrompt = if ($transcription -is [string]) { $transcription } else { $transcription | ConvertTo-Json -Depth 10 -Compress }

    $logParams = @{
        Model           = $ModelId
        SystemPrompt    = ''
        UserPrompt      = "Audio file: $AudioFile (Language: $Language)"
        AssistantPrompt = $assistantPrompt
    }
    if ($PSBoundParameters.ContainsKey('LogFilePath')) {
        $logParams['LogFilePath'] = $LogFilePath
    }
    New-FoundryLogEntries @logParams

    return $transcription
}
