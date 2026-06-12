#Requires -Version 7.0

function Test-FoundryModelName {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$ModelName
    )

    $models = Get-FoundryModelList

    # Foundry CLI 0.10.0+ appends a ':version' suffix to catalogue ids
    # (e.g. 'qwen2.5-0.5b-instruct-generic-cpu:4'); accept the id with or without it.
    return [bool]($models | Where-Object {
        $_.id -eq $ModelName -or ($_.id -split ':')[0] -eq $ModelName
    })
}
