#Requires -Version 7.0

function Get-FoundryServicePort {
    [CmdletBinding()]
    [OutputType([int])]
    param()

$versionInfo = Get-FoundryVersion
$useNewApi = $versionInfo.Source -eq 'SDK' -or (
        $versionInfo.Version -and ([version]$versionInfo.Version -ge [version]'0.10.0')
    )

    if ($useNewApi) {
        $FoundryCmd = "server"
    }
    else {
        $FoundryCmd = "service"
    }

        $status = Invoke-FoundryCli -Arguments @($FoundryCmd, 'status')
    

    if (@($status) -imatch 'Not running') {
        Write-Verbose 'Foundry service is not running — starting it now.'
        Invoke-FoundryCli -Arguments @($FoundryCmd, 'start') | Out-Null
        $status = Invoke-FoundryCli -Arguments @($FoundryCmd, 'status')

        if (@($status) -imatch 'Not running') {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Foundry service failed to start.'),
                    'FoundryServiceStartFailed',
                    [System.Management.Automation.ErrorCategory]::ResourceUnavailable,
                    $null
                )
            )
        }
    }

    if ($useNewApi) {
        $urlLine = @($status) | Where-Object { $_ -match 'http://' } | Select-Object -First 1
        $port = ([regex]'(?<=:)\d+\s*$').Match($urlLine).Value
    } else {
        $port = ([regex]'(?<=:)\d+(?=/)').Match($status).Value
    }

    if (-not $port) {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Could not determine Foundry service port from status output.'),
                'FoundryServicePortNotFound',
            [System.Management.Automation.ErrorCategory]::ResourceUnavailable,
                $null
            )
        )
    }

    return [int]$port
}
