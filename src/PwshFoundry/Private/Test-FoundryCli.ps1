function Test-FoundryCli {
    [CmdletBinding()]
    param(
        [string]$BinName = 'foundry'
    )
    $cmd = Get-Command $BinName -ErrorAction SilentlyContinue

    if (-not $cmd) {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.IO.FileNotFoundException]::new(
                    "Foundry CLI not found. Install it and ensure it is on PATH."),
                'FoundryCliNotFound',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                $null
            )
        )
    }
    $script:FoundryCliBin = $cmd.Source
    $cmd
}
