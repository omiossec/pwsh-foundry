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
    param(
        [switch]$ByPassCache,

        [Parameter()]
        [int]$Port
    )

    if (-not $ByPassCache) {
        $cacheAgeMinutes = if ($script:FoundryModelCacheTime) {
            ([datetime]::UtcNow - $script:FoundryModelCacheTime).TotalMinutes
        } else {
            [double]::MaxValue
        }

        if ($script:FoundryModelCache -and $cacheAgeMinutes -lt 60) {
            return $script:FoundryModelCache
        }
    }

    $apiParams = @{ Action = 'model-list'; Method = 'GET' }
    if ($PSBoundParameters.ContainsKey('Port')) { $apiParams['Port'] = $Port }
    $response = Invoke-FoundryApiRequest @apiParams

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
        'uri'
        'providerType'
        'version'
        'promptTemplate'
        'publisher'
        'task'
        @{ Name = 'deviceType'; Expression = { $_.runtime.deviceType } }
        'maxOutputTokens'
    )

    $script:FoundryModelCache = @($items | Select-Object -Property $selectedProperties)
    $script:FoundryModelCacheTime = [datetime]::UtcNow

    return $script:FoundryModelCache
}
