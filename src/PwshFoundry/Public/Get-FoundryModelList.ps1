#Requires -Version 7.0

function Get-FoundryModelList {
    <#
    .SYNOPSIS
        Lists AI models available to run or download from Foundry.
    .DESCRIPTION
        Returns the full model catalogue with a projected set of properties for
        each model. Uses the Foundry CLI (`foundry model list --output json`)
        when it is installed, and falls back to the Azure AI Foundry Local SDK
        (via a compiled .NET host) when only the SDK is available.
    .EXAMPLE
        Get-FoundryModelList
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [switch]$ByPassCache
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

    if ((Get-FoundryVersion).Source -eq 'SDK') {
        $items = Get-FoundryModelListFromSdk
    }
    else {
        $response = Invoke-FoundryCli -Arguments @('model', 'list') -Json

        $items = if ($response.models) {
            $response.models
        } elseif ($response -is [array]) {
            $response
        } else {
            @()
        }
    }

    if (-not $items) {
        return @()
    }

    $selectedProperties = @(
        'alias'
        'id'
        'displayName'
        'type'
        'device'
        'fileSizeMb'
        'cached'
        'license'
        'supportsToolCalling'
    )

    $script:FoundryModelCache = @($items | Select-Object -Property $selectedProperties)
    $script:FoundryModelCacheTime = [datetime]::UtcNow

    return $script:FoundryModelCache
}
