#Requires -Version 7.0

function Save-FoundryModel {
    <#
    .SYNOPSIS
        Downloads a model to the local Foundry service.
    .DESCRIPTION
        Validates that the model ID exists in the local Foundry catalogue, then
        POSTs a download request to /openai/download so Foundry fetches the model
        from the given URI.
    .EXAMPLE
        Save-FoundryModel -ModelID 'Phi-4-mini-instruct-generic-cpu:4' `
                          -ModelURI 'azureml://registries/azureml/models/Phi-4-mini-instruct-generic-cpu/versions/4'
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [string]$ModelURI,

        [Parameter()]
        [string]$ProviderType = 'AzureFoundryLocal',

        [Parameter(Mandatory)]
        [string]$ModelID
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

    $body = @{
        model = @{
            Uri          = $ModelURI
            ProviderType = $ProviderType
            Name         = $ModelID
        }
    }

    Invoke-FoundryApiRequest -Path '/openai/download' -Method POST -Body $body
}
