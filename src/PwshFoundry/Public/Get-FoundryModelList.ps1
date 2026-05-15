#Requires -Version 7.0

function Get-FoundryModelList {
    <#
    .SYNOPSIS
        Lists AI models available to run or download from Foundry.
    .DESCRIPTION
        Queries the Foundry local service REST API for the full model catalogue.
        Starts the Foundry service automatically if it is not running.
        Returns a projected set of properties for each model.
    .EXAMPLE
        Get-FoundryModelList
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param()

    $response = Invoke-FoundryApiRequest -Path '/foundry/list' -Method GET

    $items = if ($response -is [array]) {
        $response
    } elseif ($response.data) {
        $response.data
    } else {
        @()
    }

    if (-not $items) {
        return @()
    }

    $selectedProperties = @(
        'name'
        'displayName'
        'providerType'
        'version'
        'promptTemplate'
        'publisher'
        'task'
        @{ Name = 'deviceType'; Expression = { $_.runtime.deviceType } }
        'maxOutputTokens'
    )

    return @($items | Select-Object -Property $selectedProperties)
}
