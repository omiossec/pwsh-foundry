function Test-FoundryLogFilePath {
    <#
    .SYNOPSIS
        Validates that a path is syntactically valid and its parent directory exists.
    .DESCRIPTION
        Used to check a user-supplied -LogFilePath before it is passed to
        New-FoundryLogEntries, so a bad path fails fast with a clear error
        instead of failing later inside Add-Content.
    .PARAMETER Path
        The candidate log file path to validate.
    .EXAMPLE
        Test-FoundryLogFilePath -Path 'C:\logs\foundry.jsonl'
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path -IsValid)) {
        return $false
    }

    $parent = Split-Path -Path $Path -Parent

    if ([string]::IsNullOrWhiteSpace($parent)) {
        return $true
    }

    return Test-Path -Path $parent -PathType Container
}
