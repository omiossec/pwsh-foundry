#Requires -Version 7.0

function Initialize-FoundryModel {
    <#
    .SYNOPSIS
        Makes sure a model is loaded in the Foundry service and returns its versioned id.
    .DESCRIPTION
        Since Foundry Local 0.10.0 the OpenAI-compatible endpoints no longer auto-load models.
        Foundry Local 0.11.0+ is also inconsistent about names: /models/load only accepts the
        alias ('qwen3-0.6b'), while /v1/chat/completions and /v1/embeddings expect the versioned
        id ('qwen3-0.6b-generic-gpu:1').

        This helper accepts an alias, an id or a versioned id, loads the model by alias when no
        matching variant is loaded, and returns the versioned id of the loaded variant so callers
        can put it in the request body. It returns nothing when the name is not in the catalog.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    $catalogMatches = @(Resolve-FoundryModel -Name $Name)
    if ($catalogMatches.Count -eq 0) {
        return
    }

    # When an id is given, prefer that exact variant over the other devices of the same alias.
    $requested = @($catalogMatches | Where-Object { $_.id -eq $Name -or ($_.id -split ':')[0] -eq $Name })
    $preferred = if ($requested) { $requested } else { $catalogMatches }

    $loadedModels = @(Invoke-FoundryApiRequest -Action 'models-loaded' -Method GET | ForEach-Object { "$_" })
    $loadedMatch = $preferred | Where-Object { $_.id -in $loadedModels } | Select-Object -First 1
    if ($loadedMatch) {
        return $loadedMatch.id
    }

    $alias = $catalogMatches[0].alias
    Write-Verbose "Model '$Name' is not loaded; loading '$alias' now (this can take a while)."
    try {
        $null = Invoke-FoundryApiRequest -Action 'model-load' -Method GET -PathParameters @{ name = $alias } `
            -ErrorAction Stop
    }
    catch {
        if ("$($_.Exception.Message)" -match 'not cached') {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new(
                        "Model '$Name' is not downloaded. Download it first with " +
                        "Save-FoundryModel -ModelID '$Name' (or 'foundry model download $Name')."
                    ),
                    'FoundryModelNotCached',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $Name
                )
            )
        }
        $PSCmdlet.ThrowTerminatingError($_)
    }

    # Loading by alias lets Foundry pick the variant for this device; use the one it loaded.
    $loadedModels = @(Invoke-FoundryApiRequest -Action 'models-loaded' -Method GET | ForEach-Object { "$_" })
    $loadedMatch = $preferred | Where-Object { $_.id -in $loadedModels } | Select-Object -First 1
    if (-not $loadedMatch) {
        $loadedMatch = $catalogMatches | Where-Object { $_.id -in $loadedModels } | Select-Object -First 1
        if ($loadedMatch -and $requested) {
            Write-Warning ("Foundry loaded '$($loadedMatch.id)' for alias '$alias' instead of the requested " +
                "'$Name'. Load the variant you want with Save-FoundryModel or 'foundry model load'.")
        }
    }

    if ($loadedMatch) {
        return $loadedMatch.id
    }
    return $preferred[0].id
}
