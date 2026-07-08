#Requires -Version 7.0

function Invoke-FoundryApiRequest {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter()]
        [string]$FoundryHost = 'http://localhost',

        [Parameter()]
        [ValidateRange(1, 65535)]
        [int]$Port,

        [Parameter(Mandatory)]
        [ValidateSet('chat', 'transcribe', 'status', 'model-list', 'models-loaded',
                     'model-load', 'model-unload', 'tokenizer')]
        [string]$Action,

        [Parameter()]
        [hashtable]$PathParameters,

        [Parameter()]
        [hashtable]$Headers,

        [Parameter()]
        [object]$Body,

        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PUT', 'HEAD')]
        [string]$Method
    )

    $pathMap = @{
        'chat'           = @{ Old = '/v1/chat/completions';                        New = '/v1/chat/completions' }
        'transcribe'     = @{ Old = '/v1/audio/transcriptions';                    New = '/v1/audio/transcriptions' }
        'status'         = @{ Old = '/openai/status';                              New = '/status' }
        'model-list'     = @{ Old = '/foundry/list';                               New = '/v1/models' }
        'models-loaded'  = @{ Old = '/openai/models';                              New = '/models/loaded' }
        'model-load'     = @{ Old = '/openai/load/{name}';                         New = '/models/load/{name}' }
        'model-unload'   = @{ Old = '/openai/unload/{name}';                       New = '/models/unload/{name}' }
        'model-download' = @{ Old = '/openai/download';                            New = $null }
        'tokenizer'      = @{ Old = '/v1/chat/completions/tokenizer/encode/count'; New = $null }
    }

    $versionInfo = Get-FoundryVersion
    $useNewApi = $versionInfo.Source -eq 'SDK' -or (
        $versionInfo.Version -and ([version]$versionInfo.Version -ge [version]'0.10.0')
    )

    $pathTemplate = if ($useNewApi) { $pathMap[$Action].New } else { $pathMap[$Action].Old }

    if ($null -eq $pathTemplate) {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.InvalidOperationException]::new(
                    "Action '$Action' is not supported in the current Foundry version ($($versionInfo.Version ?? $versionInfo.Source))."
                ),
                'FoundryActionNotSupported',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $Action
            )
        )
    }

    $path = $pathTemplate
    if ($PathParameters) {
        foreach ($key in $PathParameters.Keys) {
            $path = $path -replace "\{$key\}", [uri]::EscapeDataString($PathParameters[$key])
        }
    }

    if (-not $PSBoundParameters.ContainsKey('Port')) {
        $Port = Get-FoundryServicePort
    }

    $uri = '{0}:{1}{2}' -f $FoundryHost.TrimEnd('/'), $Port, $path
    Write-Debug "Foundry API $Method $uri"

    $invokeParams = @{
        Uri                      = $uri
        Method                   = $Method
        OperationTimeoutSeconds  = 120
        ConnectionTimeoutSeconds = 120
    }

    if ($PSBoundParameters.ContainsKey('Body')) {
        $invokeParams['Body'] = $Body | ConvertTo-Json -Depth 10 -Compress
        $invokeParams['ContentType'] = 'application/json'
    }

    if ($Headers) {
        $invokeParams['Headers'] = $Headers
    }

    try {
        Invoke-RestMethod @invokeParams
    }
    catch {
        $message = "Foundry API request failed ($Method $uri): $($_.Exception.Message)"
        if ($_.ErrorDetails.Message) {
            $message += " Server response: $($_.ErrorDetails.Message)"
        }
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new($message),
                'FoundryApiRequestError',
                [System.Management.Automation.ErrorCategory]::ConnectionError,
                $uri
            )
        )
    }
}
