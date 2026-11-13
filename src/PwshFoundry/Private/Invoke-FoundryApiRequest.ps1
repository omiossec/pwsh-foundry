#Requires -Version 7.0

function Invoke-FoundryApiRequest {
    <#
    .SYNOPSIS
        Sends a request to the local Foundry service REST API.
    .DESCRIPTION
        Maps a logical action to the route of the installed Foundry Local version, fills the path
        parameters and the query string, and calls the service with Invoke-RestMethod.

        Foundry Local 0.10.0 changed most routes (the 'Old' and 'New' paths of the route map).
        Actions with a MinVersion (for example the 0.14.0 Responses, decision and ranking routes)
        fail with a clear error when the installed CLI is older.

        -Catalog Local sends the request to the Local Catalog (BYOM) mount (/catalogs/local), which
        serves the same routes for models registered locally. /status and /shutdown only exist at
        the root.

        Errors returned by the service use the OpenAI envelope {"error":{"message","type","code"}};
        the message and code are surfaced in the terminating error.
    .PARAMETER Action
        Logical name of the route to call.
    .PARAMETER PathParameters
        Values for the {placeholders} of the route, for example @{ name = 'qwen3-0.6b' }.
    .PARAMETER Query
        Query string parameters. $null values are skipped and booleans are sent as true/false.
    .PARAMETER Catalog
        'Public' (default) for the Microsoft catalog, 'Local' for the BYOM catalog.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter()]
        [string]$FoundryHost = 'http://localhost',

        [Parameter()]
        [ValidateRange(1, 65535)]
        [int]$Port,

        [Parameter(Mandatory)]
        [ValidateSet('chat', 'embeddings', 'transcribe', 'status', 'shutdown', 'model-list', 'model-get',
                     'models-loaded', 'model-load', 'model-unload', 'model-download', 'tokenizer',
                     'decision', 'rank', 'response-create', 'response-list', 'response-get',
                     'response-delete', 'response-input-items')]
        [string]$Action,

        [Parameter()]
        [hashtable]$PathParameters,

        [Parameter()]
        [hashtable]$Query,

        [Parameter()]
        [hashtable]$Headers,

        [Parameter()]
        [object]$Body,

        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PUT', 'DELETE', 'HEAD')]
        [string]$Method,

        [Parameter()]
        [ValidateSet('Public', 'Local')]
        [string]$Catalog = 'Public'
    )

    # Old = route before Foundry Local 0.10.0, New = route since 0.10.0 ($null = not available).
    # MinVersion = first CLI version serving the route. RootOnly = not mounted under /catalogs/local.
    $routeMap = @{
        'chat'                 = @{ Old = '/v1/chat/completions'; New = '/v1/chat/completions' }
        'embeddings'           = @{ Old = $null; New = '/v1/embeddings' }
        'transcribe'           = @{ Old = '/v1/audio/transcriptions'; New = '/v1/audio/transcriptions' }
        'status'               = @{ Old = '/openai/status'; New = '/status'; RootOnly = $true }
        'shutdown'             = @{ Old = $null; New = '/shutdown'; MinVersion = '0.14.0'; RootOnly = $true }
        'model-list'           = @{ Old = '/foundry/list'; New = '/v1/models' }
        'model-get'            = @{ Old = $null; New = '/v1/models/{name}'; MinVersion = '0.14.0' }
        'models-loaded'        = @{ Old = '/openai/models'; New = '/models/loaded' }
        'model-load'           = @{ Old = '/openai/load/{name}'; New = '/models/load/{name}' }
        'model-unload'         = @{ Old = '/openai/unload/{name}'; New = '/models/unload/{name}' }
        'model-download'       = @{ Old = '/openai/download'; New = $null }
        'tokenizer'            = @{ Old = '/v1/chat/completions/tokenizer/encode/count'; New = $null }
        'decision'             = @{ Old = $null; New = '/v1/systemone'; MinVersion = '0.14.0' }
        'rank'                 = @{ Old = $null; New = '/v1/rank'; MinVersion = '0.14.0' }
        'response-create'      = @{ Old = $null; New = '/v1/responses'; MinVersion = '0.14.0' }
        'response-list'        = @{ Old = $null; New = '/v1/responses'; MinVersion = '0.14.0' }
        'response-get'         = @{ Old = $null; New = '/v1/responses/{id}'; MinVersion = '0.14.0' }
        'response-delete'      = @{ Old = $null; New = '/v1/responses/{id}'; MinVersion = '0.14.0' }
        'response-input-items' = @{ Old = $null; New = '/v1/responses/{id}/input_items'; MinVersion = '0.14.0' }
    }
    $route = $routeMap[$Action]

    $versionInfo = Get-FoundryVersion
    $installedVersion = if ($versionInfo.Version) { [version]$versionInfo.Version } else { $null }
    $useNewApi = $versionInfo.Source -eq 'SDK' -or ($installedVersion -and $installedVersion -ge [version]'0.10.0')
    $versionLabel = $versionInfo.Version ?? $versionInfo.Source

    $pathTemplate = if ($useNewApi) { $route.New } else { $route.Old }
    $tooOld = $route.MinVersion -and $versionInfo.Source -eq 'CLI' -and $installedVersion -and
        $installedVersion -lt [version]$route.MinVersion

    if ($null -eq $pathTemplate -or $tooOld) {
        $reason = if ($route.MinVersion) { " It requires Foundry Local $($route.MinVersion) or later." } else { '' }
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.InvalidOperationException]::new(
                    "Action '$Action' is not supported in the current Foundry version ($versionLabel).$reason"
                ),
                'FoundryActionNotSupported',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $Action
            )
        )
    }

    if ($Catalog -eq 'Local') {
        if ($route.RootOnly -or -not $useNewApi) {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.ArgumentException]::new(
                        "Action '$Action' is not available on the Local Catalog (BYOM) API."
                    ),
                    'FoundryCatalogNotSupported',
                    [System.Management.Automation.ErrorCategory]::InvalidArgument,
                    $Action
                )
            )
        }
        $pathTemplate = '/catalogs/local' + $pathTemplate
    }

    $path = $pathTemplate
    if ($PathParameters) {
        foreach ($key in $PathParameters.Keys) {
            $path = $path -replace "\{$key\}", [uri]::EscapeDataString("$($PathParameters[$key])")
        }
    }

    if ($Query) {
        $pairs = foreach ($key in ($Query.Keys | Sort-Object)) {
            $value = $Query[$key]
            if ($null -eq $value) { continue }
            if ($value -is [bool]) { $value = "$value".ToLowerInvariant() }
            '{0}={1}' -f [uri]::EscapeDataString($key), [uri]::EscapeDataString("$value")
        }
        if ($pairs) {
            $path += '?' + ($pairs -join '&')
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
        $invokeParams['Body'] = $Body | ConvertTo-Json -Depth 20 -Compress
        $invokeParams['ContentType'] = 'application/json'
    }

    if ($Headers) {
        $invokeParams['Headers'] = $Headers
    }

    try {
        Invoke-RestMethod @invokeParams
    }
    catch {
        $statusCode = $null
        if ($_.Exception.PSObject.Properties['Response'] -and $_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }

        $message = "Foundry API request failed ($Method $uri)"
        if ($statusCode) {
            $message += ": HTTP $statusCode"
        }

        $serverMessage = $null
        $serverCode = $null
        $rawDetails = $_.ErrorDetails.Message
        if ($rawDetails) {
            try {
                $envelope = $rawDetails | ConvertFrom-Json -ErrorAction Stop
                if ($envelope.error) {
                    $serverMessage = if ($envelope.error -is [string]) { $envelope.error } else { $envelope.error.message }
                    $serverCode = if ($envelope.error -isnot [string]) { $envelope.error.code } else { $null }
                }
                elseif ($envelope.message) {
                    $serverMessage = $envelope.message
                }
            }
            catch {
                Write-Debug "Foundry API error body is not JSON: $rawDetails"
            }
        }

        if ($serverMessage) {
            $message += " - $serverMessage"
            if ($serverCode) {
                $message += " ($serverCode)"
            }
        }
        elseif ($rawDetails) {
            $message += " - Server response: $rawDetails"
        }
        else {
            $message += " - $($_.Exception.Message)"
        }

        switch ($statusCode) {
            503 {
                $message += ' The Foundry service is busy or is not accepting requests; ' +
                    'check it with "foundry server status" and retry.'
            }
            409 {
                $message += ' The model on disk does not match the expected model path.'
            }
            499 {
                $message += ' The request was cancelled before the service answered.'
            }
        }

        $category = switch ($statusCode) {
            { $_ -in 400, 422 } { [System.Management.Automation.ErrorCategory]::InvalidArgument; break }
            404 { [System.Management.Automation.ErrorCategory]::ObjectNotFound; break }
            403 { [System.Management.Automation.ErrorCategory]::PermissionDenied; break }
            409 { [System.Management.Automation.ErrorCategory]::ResourceExists; break }
            503 { [System.Management.Automation.ErrorCategory]::ResourceBusy; break }
            default { [System.Management.Automation.ErrorCategory]::ConnectionError }
        }

        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new($message, $_.Exception),
                'FoundryApiRequestError',
                $category,
                $uri
            )
        )
    }
}
