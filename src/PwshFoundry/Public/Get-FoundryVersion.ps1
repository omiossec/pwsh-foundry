function Get-FoundryVersion {
    <#
    .SYNOPSIS
        Returns the installed Foundry CLI version.
    #>
    [CmdletBinding()]
    param()
    Invoke-FoundryCli -Arguments @('--version')
}
