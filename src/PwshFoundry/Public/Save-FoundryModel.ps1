#Requires -Version 7.0

function Save-FoundryModel {
    <#
    .SYNOPSIS
        Downloads a model into the local Foundry cache, and optionally loads it.
    .DESCRIPTION
        Validates the model against the local Foundry catalog, then runs
        `foundry model download` to fetch it into the local cache. The Foundry Local
        service has no download endpoint, and /models/load refuses models that are not
        cached, so the download always goes through the Foundry CLI.

        Models that are already cached are not downloaded again unless -Force is used.
        With -Load, the model is then loaded into the running Foundry service.
    .PARAMETER ModelID
        Model alias ('whisper-small'), id ('openai-whisper-small-generic-cpu') or versioned id
        ('openai-whisper-small-generic-cpu:4'). Use Get-FoundryModelList to list them.
    .PARAMETER Force
        Downloads the model again even if it is already in the local cache. A model that is
        loaded is unloaded for the download and loaded again afterwards.
    .PARAMETER Load
        Loads the model into the Foundry service once it is downloaded.
    .PARAMETER Port
        Port of the Foundry service, used with -Load. Discovered automatically when omitted.
    .EXAMPLE
        Save-FoundryModel -ModelID 'phi-4-mini'
    .EXAMPLE
        Save-FoundryModel -ModelID 'openai-whisper-small-generic-cpu:4' -Load
    .OUTPUTS
        An object with the Alias, Id, Downloaded, Loaded and Message properties. Downloaded is
        $false when the model was already cached.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ModelID,

        [switch] $Force,

        [switch] $Load,

        [Parameter()]
        [ValidateRange(1, 65535)]
        [int] $Port
    )

    $catalogMatches = @(Resolve-FoundryModel -Name $ModelID)
    if ($catalogMatches.Count -eq 0) {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.ArgumentException]::new(
                    "Model '$ModelID' does not exist in the local Foundry catalogue. Use Get-FoundryModelList to get a valid model ID."
                ),
                'FoundryModelNotFound',
                [System.Management.Automation.ErrorCategory]::InvalidArgument,
                $ModelID
            )
        )
    }

    $sizeMb = ($catalogMatches | Measure-Object -Property fileSizeMb -Maximum).Maximum
    if (-not $PSCmdlet.ShouldProcess($ModelID, "Download model ($sizeMb MB) into the local Foundry cache")) {
        return
    }

    $apiPortParams = @{}
    if ($PSBoundParameters.ContainsKey('Port')) {
        $apiPortParams['Port'] = $Port
    }

    $arguments = @('model', 'download', $ModelID)
    $reloadAlias = $null
    if ($Force) {
        $arguments += '--force'

        # The CLI refuses to replace a model that is loaded, so unload it first and reload it afterwards.
        # When the service is not running nothing is loaded, so a failed lookup is not an error.
        $loadedModels = try {
            @(Invoke-FoundryApiRequest -Action 'models-loaded' -Method GET @apiPortParams | ForEach-Object { $_ })
        } catch {
            Write-Verbose "Could not list loaded models, assuming none: $($_.Exception.Message)"
            @()
        }
        $loadedEntry = $catalogMatches | Where-Object { $_.id -in $loadedModels } | Select-Object -First 1
        if ($loadedEntry) {
            Write-Verbose "Unloading '$($loadedEntry.alias)' before re-downloading it."
            $null = Invoke-FoundryApiRequest -Action 'model-unload' -Method GET -PathParameters @{
                name = $loadedEntry.alias
            } @apiPortParams
            $reloadAlias = $loadedEntry.alias
        }
    }

    Write-Verbose "Invoking: foundry $($arguments -join ' ') --output json"
    $result = Invoke-FoundryCli -Arguments $arguments -Json

    if (-not $result.success) {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.InvalidOperationException]::new(
                    "Foundry failed to download '$ModelID': $($result.message ?? $result.error ?? $result.info)"
                ),
                'FoundryModelDownloadFailed',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $ModelID
            )
        )
    }

    # The CLI reports a fresh download in 'message' and an already cached model in 'info',
    # both naming the versioned id it picked for this device.
    $message = $result.message ?? $result.info
    $downloaded = [bool]$result.message

    $catalogMatches = @(Resolve-FoundryModel -Name $ModelID -ByPassCache)
    $entry = if ($message -match "'([^']+)'") {
        $catalogMatches | Where-Object { $_.id -eq $Matches[1] } | Select-Object -First 1
    }
    if (-not $entry) {
        $entry = $catalogMatches | Where-Object { $_.cached } | Select-Object -First 1
    }
    if (-not $entry) {
        $entry = $catalogMatches[0]
    }

    $loaded = $false
    if ($Load -or $reloadAlias) {
        $loadAlias = $reloadAlias ?? $entry.alias
        Write-Verbose "Loading '$loadAlias' into the Foundry service."
        $null = Invoke-FoundryApiRequest -Action 'model-load' -Method GET -PathParameters @{
            name = $loadAlias
        } @apiPortParams
        $loaded = $true
    }

    [PSCustomObject]@{
        Alias      = $entry.alias
        Id         = $entry.id
        Downloaded = $downloaded
        Loaded     = $loaded
        Message    = $message
    }
}
