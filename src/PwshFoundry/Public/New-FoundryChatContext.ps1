function New-FoundryChatContext {
    <#
    .SYNOPSIS
        Creates a FoundryChatContext object from a user prompt and an optional system prompt.
    .DESCRIPTION
        Builds a FoundryChatContext seeded with a system prompt and an initial user prompt.
        Use AddUserPrompt/AddAssistantResponse on the returned object to grow the conversation
        with further turns, then pass GetMessages() as the message history for subsequent
        New-FoundryChat calls.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $UserPrompt,

        [Parameter()]
        [string] $SystemPrompt
    )

    if ($PSBoundParameters.ContainsKey('SystemPrompt')) {
        return [FoundryChatContext]::new($UserPrompt, $SystemPrompt)
    }

    return [FoundryChatContext]::new($UserPrompt)
}
