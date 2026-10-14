#Requires -Version 7.0

function Resolve-FoundryModel {
    <#
    .SYNOPSIS
        Returns the catalog entries matching a model alias, id or versioned id.
    .DESCRIPTION
        Foundry Local 0.11.0 is inconsistent about model names: /models/load expects the alias
        ('whisper-small'), the OpenAI-compatible endpoints expect the versioned id
        ('openai-whisper-small-generic-cpu:4') and users may type the unversioned id. This helper
        accepts any of the three forms and returns every matching catalog entry (an alias can map
        to several device variants). It returns nothing when the name is unknown.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [switch] $ByPassCache
    )

    Get-FoundryModelList -ByPassCache:$ByPassCache | Where-Object {
        $_.id -eq $Name -or ($_.id -split ':')[0] -eq $Name -or $_.alias -eq $Name
    }
}
