function Invoke-FoundryCli {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [switch]$Json
    )
    if (-not $script:FoundryCliBin) { Test-FoundryCli | Out-Null }

    if ($Json) { $Arguments += @('--output', 'json') }

    $result = & $script:FoundryCliBin @Arguments 2>&1
    $stdout = $result | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }
    $stderr  = $result | Where-Object { $_ -is  [System.Management.Automation.ErrorRecord] }

    if ($LASTEXITCODE -ne 0) {
        $msg = ($stderr | Out-String).Trim()
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("Foundry CLI exited $LASTEXITCODE : $msg"),
                'FoundryCliError',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $Arguments
            )
        )
    }

    if ($stderr) { $stderr | ForEach-Object { Write-Warning $_.ToString() } }

    if ($Json) {
        $stdout | ConvertFrom-Json
    } else {
        $stdout
    }
}
