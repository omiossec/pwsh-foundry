<#
    Transcribes an audio file with a local Foundry Whisper model through the
    /v1/audio/transcriptions REST endpoint (Foundry Local 0.11.0+).

    The script shows three uses of New-FoundryAudioTranscription:
      1. plain transcription returned as a string (language auto-detected)
      2. the same transcription returned as an object (-ResponseFormat json)
      3. a transcription into another language (-Language), which Whisper
         produces by translating the speech

    The model is downloaded with Save-FoundryModel if it is not cached yet, and
    is loaded automatically by New-FoundryAudioTranscription on first use.

    Usage:
        ./samples/audio-transcription.ps1
        ./samples/audio-transcription.ps1 -Model whisper-tiny -AudioFile C:\recordings\meeting.wav -TargetLanguage de
#>

param(
    [Parameter()]
    [string] $Model = 'whisper-small',

    [Parameter()]
    [string] $AudioFile = (Join-Path $PSScriptRoot 'Recording.mp3'),

    [Parameter()]
    [string] $TargetLanguage = 'fr'
)

Import-Module (Join-Path $PSScriptRoot '../src/PwshFoundry/PwshFoundry.psd1') -Force

$catalogEntry = Get-FoundryModelList | Where-Object { $_.alias -eq $Model -or $_.id -like "${Model}*" } |
    Select-Object -First 1
if (-not $catalogEntry) {
    throw "Model '$Model' is not in the Foundry catalog. Run Get-FoundryModelList to list the whisper models."
}
if (-not $catalogEntry.cached) {
    Write-Output "Downloading '$($catalogEntry.alias)' ($($catalogEntry.fileSizeMb) MB)..."
    Save-FoundryModel -ModelID $catalogEntry.alias | Out-Null
}

Write-Output "Transcribing '$AudioFile' with '$Model' (first call loads the model)..."
Write-Output ''

# 1. Plain text, language auto-detected
$text = New-FoundryAudioTranscription -ModelId $Model -AudioFile $AudioFile
Write-Output '--- Transcription (text) ---'
Write-Output $text
Write-Output ''

# 2. Object output, handy for pipelines and exports
$result = New-FoundryAudioTranscription -ModelId $Model -AudioFile $AudioFile -Language 'en' -ResponseFormat 'json'
Write-Output '--- Transcription (object) ---'
$result | Format-List | Out-String | Write-Output

# 3. Transcription into another language
$translated = New-FoundryAudioTranscription -ModelId $Model -AudioFile $AudioFile -Language $TargetLanguage
Write-Output "--- Transcription in '$TargetLanguage' ---"
Write-Output $translated
