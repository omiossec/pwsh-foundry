#Requires -Version 7.0

function New-FoundryAudioTranscription {
    <#
    .SYNOPSIS
        Transcribes an audio file to text using a local Foundry speech model.
    .DESCRIPTION
        POSTs a request to the Foundry Local /v1/audio/transcriptions endpoint (available since
        Foundry Local 0.11.0) and returns the transcription.

        The endpoint does not take an uploaded file: it receives the absolute path of the audio
        file and the Foundry service reads it from disk, so the file must be readable by the
        local Foundry service.

        The model can be given as a catalog alias ('whisper-small'), a model id
        ('openai-whisper-small-generic-cpu') or a versioned id ('openai-whisper-small-generic-cpu:4').
        It is resolved against the local catalog and loaded automatically if it is not already loaded.
    .PARAMETER ModelId
        Alias or id of a local Foundry Whisper model. Use Get-FoundryModelList to list them.
    .PARAMETER AudioFile
        Path to the audio file to transcribe (.mp3, .wav, .flac, .ogg or .webm).
    .PARAMETER Language
        Language of the transcription as an ISO-639-1 code (e.g. 'en', 'fr'). When omitted, the
        model detects the language. When it differs from the spoken language, Whisper translates.
    .PARAMETER Prompt
        Optional text to guide the model's style or to continue a previous audio segment.
    .PARAMETER Temperature
        Sampling temperature between 0 and 1.
    .PARAMETER ResponseFormat
        'text' (default) returns the transcribed text as a string. 'json' returns an object with
        the Id, Text, Model, AudioFile and Language properties.
    .PARAMETER LogFilePath
        Optional path to a log file. When specified, the request and the transcription
        result are appended to this file via New-FoundryLogEntries. When omitted,
        New-FoundryLogEntries logs to its default location.
    .EXAMPLE
        New-FoundryAudioTranscription -ModelId 'whisper-small' -AudioFile 'C:\recordings\meeting.mp3'
    .EXAMPLE
        New-FoundryAudioTranscription -ModelId 'whisper-large-v3-turbo' -AudioFile './interview.wav' -Language 'fr' -ResponseFormat 'json'
    .NOTES
        Requires Foundry Local 0.11.0 or later. Long recordings are subject to the 120 second
        request timeout of the module's API client.
    #>
    [CmdletBinding()]
    [OutputType([string], [PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('(?i)whisper')]
        [string] $ModelId,

        [Parameter(Mandatory)]
        [ValidatePattern('(?i)\.(mp3|wav|flac|ogg|webm)$')]
        [string] $AudioFile,

        [Parameter()]
        [ValidatePattern('^[a-zA-Z]{2,3}$')]
        [string] $Language,

        [Parameter()]
        [string] $Prompt,

        [Parameter()]
        [ValidateRange(0.0, 1.0)]
        [double] $Temperature,

        [Parameter()]
        [ValidateSet('text', 'json')]
        [string] $ResponseFormat = 'text',

        [Parameter()]
        [string] $LogFilePath
    )

    if (-not (Test-Path -LiteralPath $AudioFile -PathType Leaf)) {
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

    $versionInfo = Get-FoundryVersion
    if ($versionInfo.Source -eq 'CLI' -and $versionInfo.Version -and
        [version]$versionInfo.Version -lt [version]'0.11.0') {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.NotSupportedException]::new(
                    "Audio transcription requires Foundry Local 0.11.0 or later (installed: $($versionInfo.Version))."
                ),
                'FoundryVersionNotSupported',
                [System.Management.Automation.ErrorCategory]::NotImplemented,
                $versionInfo.Version
            )
        )
    }

    # The transcription endpoint only accepts the versioned catalog id
    # (e.g. 'openai-whisper-small-generic-cpu:4'), while /models/load only accepts the alias.
    $catalogMatches = @(Resolve-FoundryModel -Name $ModelId)

    if ($catalogMatches.Count -eq 0) {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.ArgumentException]::new(
                    "Model '$ModelId' does not exist in the local Foundry. Use Get-FoundryModelList or 'foundry model list' to get a valid model id."
                ),
                'FoundryModelNotFound',
                [System.Management.Automation.ErrorCategory]::InvalidArgument,
                $ModelId
            )
        )
    }

    $loadedModels = @(Invoke-FoundryApiRequest -Action 'models-loaded' -Method GET | ForEach-Object { $_ })
    $loadedMatch = $catalogMatches | Where-Object { $_.id -in $loadedModels } | Select-Object -First 1

    if ($loadedMatch) {
        $resolvedModelId = $loadedMatch.id
    } else {
        $alias = $catalogMatches[0].alias
        Write-Verbose "Model '$ModelId' is not loaded; loading '$alias' now (this can take a while)."
        $null = Invoke-FoundryApiRequest -Action 'model-load' -Method GET -PathParameters @{ name = $alias }

        # Loading by alias lets Foundry pick the best variant for the device; use the one it loaded.
        $loadedModels = @(Invoke-FoundryApiRequest -Action 'models-loaded' -Method GET | ForEach-Object { $_ })
        $loadedMatch = Get-FoundryModelList |
            Where-Object { $_.alias -eq $alias -and $_.id -in $loadedModels } |
            Select-Object -First 1
        $resolvedModelId = if ($loadedMatch) { $loadedMatch.id } else { $catalogMatches[0].id }
    }

    $resolvedAudioFile = (Resolve-Path -LiteralPath $AudioFile).ProviderPath

    $body = @{
        model    = $resolvedModelId
        filename = $resolvedAudioFile
    }
    if ($PSBoundParameters.ContainsKey('Language')) {
        $body['language'] = $Language.ToLowerInvariant()
    }
    if ($PSBoundParameters.ContainsKey('Prompt')) {
        $body['prompt'] = $Prompt
    }
    if ($PSBoundParameters.ContainsKey('Temperature')) {
        $body['temperature'] = $Temperature
    }

    Write-Verbose "Transcribing '$resolvedAudioFile' with model '$resolvedModelId'."

    $response = Invoke-FoundryApiRequest -Action 'transcribe' -Method POST -Body $body
    $text = "$($response.text)".Trim()

    $logParams = @{
        Model           = $resolvedModelId
        SystemPrompt    = ''
        UserPrompt      = "Audio file: $resolvedAudioFile (Language: $($Language ? $Language : 'auto'))"
        AssistantPrompt = $text
    }
    if ($PSBoundParameters.ContainsKey('LogFilePath')) {
        $logParams['LogFilePath'] = $LogFilePath
    }
    New-FoundryLogEntries @logParams

    if ($ResponseFormat -eq 'json') {
        return [PSCustomObject]@{
            Id        = $response.id
            Text      = $text
            Model     = $resolvedModelId
            AudioFile = $resolvedAudioFile
            Language  = $Language ? $Language.ToLowerInvariant() : $null
        }
    }

    return $text
}
