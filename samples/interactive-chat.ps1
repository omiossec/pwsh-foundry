<#
    Interactive chat loop using New-FoundryChat with a FoundryChatContext, so the
    conversation history (memory) is preserved across turns. Type 'exit' or 'quit'
    to end the session.
#>

param(
    [Parameter()]
    [string] $Model = 'phi-4-mini',

    [Parameter()]
    [string] $SystemPrompt = 'You are a helpful assistant'
)

Import-Module ./src/PwshFoundry/PwshFoundry.psd1 -Force

$context = $null

while ($true) {
    $prompt = Read-Host "Your prompt (type 'exit' or 'quit' to end the session)"

    if ($prompt -in @('exit', 'quit')) {
        break
    }

    if ([string]::IsNullOrWhiteSpace($prompt)) {
        continue
    }

    if ($null -eq $context) {
        $context = New-FoundryChatContext -UserPrompt $prompt -SystemPrompt $SystemPrompt
    }
    else {
        $context.AddUserPrompt($prompt)
    }

    # New-FoundryChat adds the assistant response to $context internally when -Context is used.
    $result = New-FoundryChat -Context $context -Model $Model

    Write-Output "Assistant: $($result.message.content)"
}
