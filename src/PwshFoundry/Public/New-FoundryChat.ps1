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
    .PARAMETER Tools
        One or more FoundryTool objects (created with New-FoundryTool) the model is allowed
        to call. When the model responds with tool calls, each tool's handler is invoked
        with the model-provided arguments, the results are appended as tool messages, and
        the request is re-sent until the model produces a final answer (or MaxToolRounds
        is reached).
    .PARAMETER ToolChoice
        Controls how the model uses the supplied tools: 'auto' (model decides), 'none',
        'required', or the name of one of the Tools to force that specific call. Small
        local models often need a forced tool name to emit structured tool calls. Applies
        to the first request only; follow-up requests after tool execution revert to
        automatic so the model can produce a final answer.
    .PARAMETER MaxToolRounds
        Maximum number of tool-execution rounds before the model is forced to answer
        (tools are omitted from the final request). Defaults to 5.
    .EXAMPLE
        $msg    = New-FoundryMessage -UserPrompt 'Explain quantum computing'
        $result = New-FoundryChat -Message $msg -Model 'phi-3-mini'
    .EXAMPLE
        $ctx     = New-FoundryChatContext -UserPrompt 'Explain quantum computing'
        $result  = New-FoundryChat -Context $ctx -Model 'phi-3-mini'
        $ctx.AddUserPrompt('Now explain it to a 5 year old')
        $result2 = New-FoundryChat -Context $ctx -Model 'phi-3-mini'
    .EXAMPLE
        $tool = New-FoundryTool -Name 'Get-CurrentTime' -Description 'Returns the current local time' `
            -Handler { (Get-Date).ToString('o') }
        $ctx    = New-FoundryChatContext -UserPrompt 'What time is it right now?'
        $result = New-FoundryChat -Context $ctx -Model 'phi-3-mini' -Tools $tool
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
        [string] $LogFilePath,

        [Parameter()]
        [FoundryTool[]] $Tools,

        [Parameter()]
        [string] $ToolChoice,

        [Parameter()]
        [ValidateRange(1, 10)]
        [int] $MaxToolRounds = 5
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

    if ($PSBoundParameters.ContainsKey('Tools')) {
        $body.tools = @($Tools | ForEach-Object { $_.ToRequestObject() })

        if ($PSBoundParameters.ContainsKey('ToolChoice')) {
            if ($ToolChoice -in @('auto', 'none', 'required')) {
                $body.tool_choice = $ToolChoice
            }
            elseif ($Tools.Name -contains $ToolChoice) {
                $body.tool_choice = @{ type = 'function'; function = @{ name = $ToolChoice } }
            }
            else {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.ArgumentException]::new(
                            "ToolChoice '$ToolChoice' must be 'auto', 'none', 'required', or the name of one of the supplied Tools."
                        ),
                        'FoundryInvalidToolChoice',
                        [System.Management.Automation.ErrorCategory]::InvalidArgument,
                        $ToolChoice
                    )
                )
            }
        }
    }

    Write-Verbose "Request body: $($body | ConvertTo-Json -Depth 10)"

    $chat = Invoke-FoundryApiRequest -Action 'chat' -Method POST -Body $body

    if ($PSBoundParameters.ContainsKey('Tools')) {
        $round = 0

        while ($round -lt $MaxToolRounds -and
               $chat.choices[0].finish_reason -eq 'tool_calls' -and
               $chat.choices[0].message.tool_calls) {

            $round++
            $toolCalls = $chat.choices[0].message.tool_calls

            $messages = @($messages) + @{ role = 'assistant'; content = $null; tool_calls = $toolCalls }
            if ($PSCmdlet.ParameterSetName -eq 'Context') {
                $Context.AddAssistantToolCalls($toolCalls)
            }

            foreach ($call in $toolCalls) {
                $toolName = $call.function.name
                $tool     = $Tools | Where-Object { $_.Name -eq $toolName } | Select-Object -First 1

                $toolResult = if ($null -eq $tool) {
                    "Unknown tool '$toolName'."
                }
                else {
                    $toolArguments = if ([string]::IsNullOrWhiteSpace($call.function.arguments)) {
                        @{}
                    }
                    else {
                        $call.function.arguments | ConvertFrom-Json -AsHashtable
                    }

                    Write-Verbose "Invoking tool '$toolName' with arguments: $($call.function.arguments)"
                    $tool.Invoke($toolArguments)
                }

                $messages = @($messages) + @{ role = 'tool'; tool_call_id = $call.id; content = $toolResult }
                if ($PSCmdlet.ParameterSetName -eq 'Context') {
                    $Context.AddToolResult($call.id, $toolResult)
                }
            }

            $body.messages = $messages

            # A forced tool_choice must not apply to follow-up requests, or the model
            # would be forced to call the tool again instead of answering.
            $body.Remove('tool_choice')

            # On the last allowed round, drop the tools so the model must answer.
            if ($round -ge $MaxToolRounds) {
                $body.Remove('tools')
            }

            Write-Verbose "Tool round ${round}: re-sending request with $($toolCalls.Count) tool result(s)."
            $chat = Invoke-FoundryApiRequest -Action 'chat' -Method POST -Body $body
        }
    }

    if ($CountTokenOnly) {
        return $chat.usage
    }

    $assistantContent = $chat.choices[0].message.content

    if ($PSCmdlet.ParameterSetName -eq 'Context') {
        # A tool-calls-only final response has no text content; the context guard rejects empty strings.
        if (-not [string]::IsNullOrWhiteSpace($assistantContent)) {
            $Context.AddAssistantResponse($assistantContent)
        }
        $systemPrompt = $Context.SystemPrompt
        $userPrompt   = ($messages | Where-Object { $_.role -eq 'user' } | Select-Object -Last 1).content
    }
    else {
        $systemPrompt = $Message.SystemPrompt
        $userPrompt   = $Message.UserPrompt
    }

    if (-not [string]::IsNullOrWhiteSpace($assistantContent)) {
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
    }

    return [PSCustomObject]@{
        id            = $chat.id
        object        = $chat.object
        model         = $chat.model
        message       = $chat.choices[0].message
        usage         = $chat.usage
        successful    = $chat.successful
        finish_reason = $chat.choices[0].finish_reason
    }
}
