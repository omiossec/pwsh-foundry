#Requires -Version 7.0

function Save-FoundryModel {
    <#
    .SYNOPSIS
        Loads a model into the local Foundry service, downloading it first if needed.
    .DESCRIPTION
        Validates that the model ID exists in the local Foundry catalogue, then calls
        /models/load/{name} so Foundry fetches and loads the model. Foundry Local
        0.10+ removed the separate download-by-URI endpoint; loading by name now
        handles both fetching and loading.
    .EXAMPLE
        Save-FoundryModel -ModelID 'Phi-4-mini-instruct-generic-cpu:4'
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [string]$ModelID,

        [Parameter()]
        [int]$Port
    )

    if (-not (Test-FoundryModelName -ModelName $ModelID)) {
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

    $apiParams = @{
        Action         = 'model-load'
        Method         = 'GET'
        PathParameters = @{ name = $ModelID }
    }
    if ($PSBoundParameters.ContainsKey('Port')) { $apiParams['Port'] = $Port }
    Invoke-FoundryApiRequest @apiParams
}
