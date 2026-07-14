#Requires -Version 7.0

function Deploy-FoundryModel {
    <#
    .SYNOPSIS
        Loads a model into the local Foundry service.
    .DESCRIPTION
        Calls the Foundry 'model-load' API action so the specified model is loaded
        and ready to serve requests.
    .EXAMPLE
        Deploy-FoundryModel -Model 'Phi-4-mini-instruct-generic-cpu:4'
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [string]$Model
    )

    Invoke-FoundryApiRequest -Action 'model-load' -Method GET -PathParameters @{ name = $Model }
}
