#Requires -Version 7.0

function Test-FoundryModelName {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$ModelName
    )

    $models = Get-FoundryModelList

    return [bool]($models | Where-Object { $_.id -eq $ModelName })
}
