#Requires -Version 7.0

function New-FoundryChat {
    <#
    .SYNOPSIS
        Sends a chat completion request to the local Foundry service.
    .DESCRIPTION
        Builds an OpenAI-compatible chat completion body from a FoundryMessage or
        FoundryChatContext object and optional sampling parameters, then POSTs it to
        /v1/chat/completions.
    .PARAMETER Message
        A single-turn FoundryMessage (system prompt + user prompt). Use this for one-off
        calls that don't need conversation history.
    .PARAMETER Context
        A FoundryChatContext to use for multi-turn conversations. On a successful call the
        assistant's reply is appended to the context via AddAssistantResponse, so the same
        object can be passed back in on the next call (after calling AddUserPrompt) to keep
        growing the conversation history sent to the model.
    .PARAMETER LogFilePath
        Optional path to a log file. When specified, the system prompt, user prompt, and
        assistant response are appended to this file via New-FoundryLogEntries. When
        omitted, New-FoundryLogEntries logs to its default location.
    .EXAMPLE
        $msg    = New-FoundryMessage -UserPrompt 'Explain quantum computing'
        $result = New-FoundryChat -Message $msg -Model 'phi-3-mini'
    .EXAMPLE
        $ctx     = New-FoundryChatContext -UserPrompt 'Explain quantum computing'
        $result  = New-FoundryChat -Context $ctx -Model 'phi-3-mini'
        $ctx.AddUserPrompt('Now explain it to a 5 year old')
        $result2 = New-FoundryChat -Context $ctx -Model 'phi-3-mini'
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Message')]
        [FoundryMessage] $Message,

        [Parameter(Mandatory, ParameterSetName = 'Context')]
        [FoundryChatContext] $Context,

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
        [string] $User = 'pwshChat',

        [Parameter()]
        [switch] $CountTokenOnly,

        [Parameter()]
        [string] $LogFilePath
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

    $messages = if ($PSCmdlet.ParameterSetName -eq 'Context') { $Context.GetMessages() } else { $Message.GetMessages() }

    if ($CountTokenOnly) {
        # NOTE: This endpoint is not yet implemented in Foundry Local and currently returns HTTP 404.
        $body = @{
            model    = $Model
            messages = $messages
        }

        Write-Verbose "Request body: $($body | ConvertTo-Json -Depth 10)"

        return Invoke-FoundryApiRequest -Action 'tokenizer' -Method POST -Body $body
    }
    else {
        # Since Foundry Local 0.10.0 the OpenAI-compatible chat endpoint no longer
        # auto-loads models and returns 400 if the model is not loaded.
        $loadedModels = @(Invoke-FoundryApiRequest -Action 'models-loaded' -Method GET)
        $isLoaded = [bool]($loadedModels | Where-Object { $_ -eq $Model -or $_ -like "${Model}:*" })

        if (-not $isLoaded) {
            Write-Verbose "Model '$Model' is not loaded; loading it now (this can take a while)."
            $null = Invoke-FoundryApiRequest -Action 'model-load' -Method GET -PathParameters @{ name = $Model }
        }

        $body = @{
            model    = $Model
            messages = $messages
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

        $chat = Invoke-FoundryApiRequest -Action 'chat' -Method POST -Body $body
        $assistantContent = $chat.choices[0].message.content

        if ($PSCmdlet.ParameterSetName -eq 'Context') {
            $Context.AddAssistantResponse($assistantContent)
            $systemPrompt = $Context.SystemPrompt
            $userPrompt   = ($messages | Where-Object { $_.role -eq 'user' } | Select-Object -Last 1).content
        }
        else {
            $systemPrompt = $Message.SystemPrompt
            $userPrompt   = $Message.UserPrompt
        }

        $logParams = @{
            Model           = $Model
            SystemPrompt    = $systemPrompt
            UserPrompt      = $userPrompt
            AssistantPrompt = $assistantContent
        }
        if ($PSBoundParameters.ContainsKey('LogFilePath')) {
            $logParams['LogFilePath'] = $LogFilePath
        }
        New-FoundryLogEntries @logParams

        return [PSCustomObject]@{
            id         = $chat.id
            object     = $chat.object
            model      = $chat.model
            message    = $chat.choices[0].message
            successful = $chat.successful
        }

    }


}
