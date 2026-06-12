function Get-FoundryVersion {
    <#
    .SYNOPSIS
        Returns the installed Foundry CLI version, or indicates SDK mode when the CLI is absent.
    .DESCRIPTION
        Caches the result for 60 minutes. Use -ByPassCache to force a fresh lookup.
    .EXAMPLE
        Get-FoundryVersion
    .EXAMPLE
        Get-FoundryVersion -ByPassCache
    #>
    [CmdletBinding()]
    param(
        [switch]$ByPassCache
    )

    if (-not $ByPassCache) {
        $cacheAgeMinutes = if ($script:FoundryVersionCacheTime) {
            ([datetime]::UtcNow - $script:FoundryVersionCacheTime).TotalMinutes
        } else {
            [double]::MaxValue
        }

        if ($script:FoundryVersionCache -and $cacheAgeMinutes -lt 60) {
            return $script:FoundryVersionCache
        }
    }

    $result = try {
        $cliOutput = Invoke-FoundryCli -Arguments @('--version')
        $raw = ($cliOutput | Out-String).Trim()
        $version = if ($raw -match '(\d+\.\d+\.\d+)') { $Matches[1] } else { $null }
        [PSCustomObject]@{
            Source  = 'CLI'
            Version = $version
            Message = $raw
        }
    } catch [System.IO.FileNotFoundException] {
        [PSCustomObject]@{
            Source  = 'SDK'
            Version = $null
            Message = 'Foundry Local CLI not found — using SDK instead'
        }
    }

    $script:FoundryVersionCache     = $result
    $script:FoundryVersionCacheTime = [datetime]::UtcNow

    return $script:FoundryVersionCache
}
