#Requires -Version 7.0

function New-FoundryChat {
    <#
    .SYNOPSIS
        Sends a chat completion request to the local Foundry service.
    .DESCRIPTION
        Builds an OpenAI-compatible chat completion body from a FoundryMessage object
        and optional sampling parameters, then POSTs it to /v1/chat/completions.
    .EXAMPLE
        $msg    = New-FoundryMessage -UserPrompt 'Explain quantum computing'
        $result = New-FoundryChat -Message $msg -Model 'phi-3-mini'
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [FoundryMessage] $Message,

        [Parameter(Mandatory)]
        [string] $Model,

        [Parameter()]
        [ValidateRange(0.0, 2.0)]
        [double] $Temperature,

        [Parameter()]
        [ValidateRange(1, 2048)]
        [int] $MaxTokens,

        [Parameter()]
        [ValidateRange(0.0, 1.0)]
        [double] $TopP,

        [Parameter()]
        [ValidateRange(-2.0, 2.0)]
        [double] $PresencePenalty,

        [Parameter()]
        [ValidateRange(-2.0, 2.0)]
        [double] $FrequencyPenalty,

        [Parameter()]
        [string] $User = 'pwshChat'
    )

    if (-not (Test-FoundryModelName -ModelName $Model)) {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.ArgumentException]::new(
                    "Model '$Model' does not exist in the local Foundry. Use Get-FoundryModelList or 'foundry model list' to get a valid model id."
                ),
                'FoundryModelNotFound',
                [System.Management.Automation.ErrorCategory]::InvalidArgument,
                $Model
            )
        )
    }

    $body = @{
        model    = $Model
        messages = $Message.GetMessages()
        user     = $User
    }

    if ($PSBoundParameters.ContainsKey('Temperature')) {
        $body.temperature = $Temperature
    }

    if ($PSBoundParameters.ContainsKey('MaxTokens')) {
        $body.max_tokens = $MaxTokens
        $body.max_completion_tokens = $MaxTokens
    }

    if ($PSBoundParameters.ContainsKey('TopP')) {
        $body.top_p = $TopP
    }

    if ($PSBoundParameters.ContainsKey('PresencePenalty')) {
        $body.presence_penalty = $PresencePenalty
    }

    if ($PSBoundParameters.ContainsKey('FrequencyPenalty')) {
        $body.frequency_penalty = $FrequencyPenalty
    }

    Write-Verbose "Request body: $($body | ConvertTo-Json -Depth 10)"

    $chat = Invoke-FoundryApiRequest -Path '/v1/chat/completions' -Method POST -Body $body

    return [PSCustomObject]@{
        id         = $chat.id
        object     = $chat.object
        model      = $chat.model
        message    = $chat.choices[0].message
        successful = $chat.successful
    }
}
