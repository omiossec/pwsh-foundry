#Requires -Version 7.0

function Get-FoundryModelCache {
    <#
    .SYNOPSIS
        Lists AI models available in the local Foundry cache.
    .DESCRIPTION
        Queries the Foundry local service REST API for cached models.
        Starts the Foundry service automatically if it is not running.
    .EXAMPLE
        Get-FoundryModelCache
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param()

    $response = Invoke-FoundryApiRequest -Path '/openai/models' -Method GET

    if (-not $response -or -not $response.data) {
        return @()
    }

    return @($response.data)
}
