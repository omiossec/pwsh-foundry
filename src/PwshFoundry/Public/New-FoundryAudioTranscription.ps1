#Requires -Version 7.0

function New-FoundryAudioTranscription {
    <#
    .SYNOPSIS
        Transcribes an audio file to text using a local Foundry Whisper model.
    .DESCRIPTION
        Sends a transcription request to the local Foundry /v1/audio/transcriptions endpoint
        and returns the transcription result.
    .EXAMPLE
        New-FoundryAudioTranscription -ModelId 'whisper-1' -AudioFile 'C:\recordings\meeting.mp3'
    .EXAMPLE
        New-FoundryAudioTranscription -ModelId 'whisper-large-v3' -AudioFile './interview.wav' -Language 'fr' -ResponseFormat 'json'
    .PARAMETER LogFilePath
        Optional path to a log file. When specified, the request and the transcription
        result are appended to this file via New-FoundryLogEntries. When omitted,
        New-FoundryLogEntries logs to its default location.
    .NOTES
        This function requires Foundry Local v1.1.0 installed manually. The audio transcription
        endpoint is not available in earlier versions or in the auto-installed distribution.
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
        [ValidateRange(0.0, 1.0)]
        [double] $Temperature,

        [Parameter()]
        [ValidateSet('text', 'json', 'verbose_json')]
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

    $body = @{
        model           = $ModelId
        file            = (Resolve-Path -Path $AudioFile).Path
        language        = $Language
        response_format = $ResponseFormat
    }

    if ($PSBoundParameters.ContainsKey('Temperature')) {
        $body.temperature = $Temperature
    }

            # Since Foundry Local 0.10.0 the OpenAI-compatible chat endpoint no longer
        # auto-loads models and returns 400 if the model is not loaded.
        $loadedModels = @(Invoke-FoundryApiRequest -Action 'models-loaded' -Method GET)
        $isLoaded = [bool]($loadedModels | Where-Object { $_ -eq $ModelId -or $_ -like "${ModelId}:*" })

        if (-not $isLoaded) {
            Write-Verbose "Model '$Model' is not loaded; loading it now (this can take a while)."
            $null = Invoke-FoundryApiRequest -Action 'model-load' -Method GET -PathParameters @{ name = $Model }
        }

    Write-Verbose "Request body: $($body | ConvertTo-Json -Depth 10)"

    $transcription = Invoke-FoundryApiRequest -Action 'transcribe' -Method POST -Body $body

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
