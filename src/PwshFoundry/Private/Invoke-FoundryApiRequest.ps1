#Requires -Version 7.0

function Invoke-FoundryApiRequest {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter()]
        [string]$FoundryHost = 'http://localhost',

        [Parameter(Mandatory)]
        [ValidateRange(1, 65535)]
        [int]$Port,

        [Parameter(Mandatory)]
        [ValidatePattern('^/')]
        [string]$Path,

        [Parameter()]
        [hashtable]$Headers,

        [Parameter(Mandatory)]
        [object]$Body,

        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PUT', 'HEAD')]
        [string]$Method
    )

    $uri = '{0}:{1}{2}' -f $FoundryHost.TrimEnd('/'), $Port, $Path
    Write-Debug "Foundry API $Method $uri"

    $invokeParams = @{
        Uri         = $uri
        Method      = $Method
        ContentType = 'application/json'
        Body        = $Body | ConvertTo-Json -Depth 10 -Compress
    }

    if ($Headers) {
        $invokeParams['Headers'] = $Headers
    }

    try {
        Invoke-RestMethod @invokeParams
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("Foundry API request failed ($Method $uri): $($_.Exception.Message)"),
                'FoundryApiRequestError',
                [System.Management.Automation.ErrorCategory]::ConnectionError,
                $uri
            )
        )
    }
}
