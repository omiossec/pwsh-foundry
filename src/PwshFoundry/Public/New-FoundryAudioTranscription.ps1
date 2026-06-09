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
        [string] $ResponseFormat = 'text'
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

    $body = @{
        model           = $ModelId
        file            = (Resolve-Path -Path $AudioFile).Path
        language        = $Language
        response_format = $ResponseFormat
    }

    if ($PSBoundParameters.ContainsKey('Temperature')) {
        $body.temperature = $Temperature
    }

    Write-Verbose "Request body: $($body | ConvertTo-Json -Depth 10)"

    return Invoke-FoundryApiRequest -Action 'transcribe' -Method POST -Body $body
}
