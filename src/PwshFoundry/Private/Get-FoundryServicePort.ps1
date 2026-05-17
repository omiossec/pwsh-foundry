#Requires -Version 7.0

function Get-FoundryServicePort {
    [CmdletBinding()]
    [OutputType([int])]
    param()

    $status = Invoke-FoundryCli -Arguments @('service', 'status')

    if (@($status) -imatch 'service is not running') {
        Write-Verbose 'Foundry service is not running — starting it now.'
        Invoke-FoundryCli -Arguments @('service', 'start') | Out-Null
        $status = Invoke-FoundryCli -Arguments @('service', 'status')

        if (@($status) -imatch 'service is not running') {
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

    $port = ([regex]'(?<=:)\d+(?=/)').Match($status).Value

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
