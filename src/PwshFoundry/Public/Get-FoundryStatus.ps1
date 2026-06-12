#Requires -Version 7.0

function Get-FoundryStatus {
    <#
    .SYNOPSIS
        Returns the status of the local Foundry OpenAI-compatible endpoint.
    .DESCRIPTION
        Queries the Foundry local service REST API at /openai/status and returns
        the status object reported by the service.
    .EXAMPLE
        Get-FoundryStatus
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param()

    Invoke-FoundryApiRequest -Action 'status' -Method GET
}
