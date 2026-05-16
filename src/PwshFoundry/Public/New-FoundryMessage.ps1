function New-FoundryMessage {
    <#
    .SYNOPSIS
        Creates a FoundryMessage object from a user prompt and an optional system prompt.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $UserPrompt,

        [Parameter()]
        [string] $SystemPrompt
    )

    if ($PSBoundParameters.ContainsKey('SystemPrompt')) {
        return [FoundryMessage]::new($UserPrompt, $SystemPrompt)
    }

    return [FoundryMessage]::new($UserPrompt)
}
