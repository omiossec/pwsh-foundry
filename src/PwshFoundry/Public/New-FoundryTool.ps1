#Requires -Version 7.0

function New-FoundryTool {
    <#
    .SYNOPSIS
        Creates a FoundryTool object describing a function the model can call.
    .DESCRIPTION
        Builds a FoundryTool from a name, description, JSON-schema parameter definitions,
        and a PowerShell scriptblock handler. Pass one or more FoundryTool objects to
        New-FoundryChat -Tools to enable function calling: when the model requests a tool,
        the handler is invoked with the model-provided arguments as named parameters and
        its output is sent back to the model.
    .PARAMETER Name
        The function name exposed to the model.
    .PARAMETER Description
        A description of what the tool does; the model uses it to decide when to call it.
    .PARAMETER Parameters
        A hashtable of JSON-schema property definitions, keyed by parameter name.
        Example: @{ VnetName = @{ type = 'string'; description = 'Name of the VNet' } }
    .PARAMETER Required
        Names of the parameters the model must always provide. Each name must exist as a
        key in Parameters.
    .PARAMETER Handler
        The scriptblock executed when the model calls the tool. The model-provided
        arguments are splatted as named parameters, so declare them with param().
    .EXAMPLE
        $tool = New-FoundryTool -Name 'Get-VnetPeeringStatus' `
            -Description 'Returns the peering status of an Azure VNet' `
            -Parameters @{
                VnetName      = @{ type = 'string'; description = 'Name of the VNet' }
                ResourceGroup = @{ type = 'string'; description = 'Resource group of the VNet' }
            } `
            -Required 'VnetName', 'ResourceGroup' `
            -Handler { param($VnetName, $ResourceGroup) Get-VnetPeeringStatus @PSBoundParameters }
    #>
    [CmdletBinding()]
    [OutputType('FoundryTool')]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $Description,

        [Parameter()]
        [hashtable] $Parameters = @{},

        [Parameter()]
        [string[]] $Required = @(),

        [Parameter(Mandatory)]
        [scriptblock] $Handler
    )

    return [FoundryTool]::new($Name, $Description, $Parameters, $Required, $Handler)
}
