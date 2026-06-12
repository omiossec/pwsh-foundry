#Requires -Version 7.4

function Start-FoundryWebServer {
    <#
    .SYNOPSIS
        Starts a local Foundry web server using the Azure AI Foundry Local SDK.
    .DESCRIPTION
        Compiles and launches a minimal .NET host that calls the Microsoft.AI.Foundry.Local
        SDK to download execution providers, load the requested model, and expose an
        OpenAI-compatible HTTP endpoint.  The server runs as a background process; call
        Stop-FoundryWebServer to shut it down.  The returned object's Endpoint property
        can be passed directly to Invoke-FoundryApiRequest -FoundryHost or any OpenAI
        SDK client.
    .PARAMETER ModelAlias
        Alias or model ID recognised by the local Foundry catalog, e.g. 'qwen2.5-0.5b'.
    .PARAMETER Port
        TCP port the web service will listen on.  Defaults to 52495.
    .PARAMETER AppName
        Application name passed to the Foundry SDK for telemetry.
    .PARAMETER LogLevel
        Verbosity of SDK-internal log output written to stderr.  Defaults to Warning.
    .PARAMETER TimeoutSeconds
        Maximum seconds to wait for the server to signal readiness.  Defaults to 300.
    .OUTPUTS
        PSCustomObject  with Endpoint, ModelId, Port, and ProcessId.
    .EXAMPLE
        $srv = Start-FoundryWebServer -ModelAlias 'qwen2.5-0.5b'
        # $srv.Endpoint -> "http://127.0.0.1:52495/v1"
        Invoke-FoundryApiRequest -FoundryHost 'http://127.0.0.1' -Port 52495 -Action 'model-list' -Method GET
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$ModelAlias,

        [Parameter()]
        [ValidateRange(1, 65535)]
        [int]$Port = 52495,

        [Parameter()]
        [string]$AppName = 'pwsh_foundry',

        [Parameter()]
        [ValidateSet('Trace', 'Debug', 'Information', 'Warning', 'Error', 'Critical', 'None')]
        [string]$LogLevel = 'Warning',

        [Parameter()]
        [ValidateRange(30, 600)]
        [int]$TimeoutSeconds = 300
    )

    if ($script:FoundryWebServerProcess -and -not $script:FoundryWebServerProcess.HasExited) {
        Write-Warning "Foundry web server is already running at '$script:FoundryWebServerEndpoint'. Call Stop-FoundryWebServer first."
        return [PSCustomObject]@{
            Endpoint  = $script:FoundryWebServerEndpoint
            ModelId   = $script:FoundryWebServerModelId
            Port      = $Port
            ProcessId = $script:FoundryWebServerProcess.Id
        }
    }

    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("The 'dotnet' CLI was not found on PATH. Install the .NET SDK from https://dot.net"),
                'DotNetSdkNotFound',
                [System.Management.Automation.ErrorCategory]::NotInstalled,
                'dotnet'
            )
        )
        return
    }

    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "FoundryWebServer_$(New-Guid)"
    $null = New-Item -ItemType Directory -Path $tempDir -ErrorAction Stop

    $proc    = $null
    $started = $false

    try {
        $programCs = @'
using Microsoft.AI.Foundry.Local;
using Microsoft.Extensions.Logging.Abstractions;

var modelAlias  = args.Length > 0 ? args[0] : throw new ArgumentException("Model alias required");
var port        = args.Length > 1 ? args[1] : "52495";
var appName     = args.Length > 2 ? args[2] : "pwsh_foundry";
var logLevelArg = args.Length > 3 ? args[3] : "Warning";
var logLevel    = Enum.Parse<Microsoft.AI.Foundry.Local.LogLevel>(logLevelArg, ignoreCase: true);

var config = new Configuration
{
    AppName  = appName,
    LogLevel = logLevel,
    Web      = new Configuration.WebService { Urls = $"http://127.0.0.1:{port}" }
};

Console.Error.WriteLine($"[foundry-web] Initializing (app={appName}, port={port})...");
await FoundryLocalManager.CreateAsync(config, NullLogger.Instance);
var mgr = FoundryLocalManager.Instance;

Console.Error.WriteLine("[foundry-web] Registering execution providers...");
var lastEp = "";
await mgr.DownloadAndRegisterEpsAsync((ep, pct) =>
{
    if (ep != lastEp) { if (lastEp != "") Console.Error.WriteLine(); lastEp = ep; }
    Console.Error.Write($"\r  {ep,-30}  {pct,6:F1}%");
});
if (lastEp != "") Console.Error.WriteLine();

Console.Error.WriteLine("[foundry-web] Fetching model catalog...");
var catalog = await mgr.GetCatalogAsync();
var model   = await catalog.GetModelAsync(modelAlias)
    ?? throw new Exception($"Model '{modelAlias}' not found in the Foundry catalog.");

Console.Error.WriteLine($"[foundry-web] Preparing model '{model.Id}'...");
await model.DownloadAsync(pct => Console.Error.Write($"\r  Download: {pct,6:F1}%"));
Console.Error.WriteLine();

Console.Error.WriteLine($"[foundry-web] Loading model '{model.Id}'...");
await model.LoadAsync();

Console.Error.WriteLine($"[foundry-web] Starting web service on http://127.0.0.1:{port}...");
await mgr.StartWebServiceAsync();

Console.WriteLine($"FOUNDRY_READY endpoint=http://127.0.0.1:{port}/v1 model={model.Id}");
Console.Out.Flush();
Console.Error.WriteLine("[foundry-web] Ready. Waiting for shutdown signal...");

using var cts = new CancellationTokenSource();
Console.CancelKeyPress += (_, e) => { e.Cancel = true; cts.Cancel(); };

try { await Task.Delay(Timeout.Infinite, cts.Token); }
catch (OperationCanceledException) { }

Console.Error.WriteLine("[foundry-web] Shutting down...");
await mgr.StopWebServiceAsync();
await model.UnloadAsync();
Console.Error.WriteLine("[foundry-web] Done.");
'@

        $csproj = @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0-windows10.0.18362</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <UseCurrentRuntimeIdentifier>true</UseCurrentRuntimeIdentifier>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.AI.Foundry.Local.WinML" Version="1.2.0" />
  </ItemGroup>
</Project>
'@

        Set-Content -Path (Join-Path $tempDir 'Program.cs')              -Value $programCs -Encoding utf8
        Set-Content -Path (Join-Path $tempDir 'FoundryWebServer.csproj') -Value $csproj    -Encoding utf8

        Write-Verbose "Building Foundry web server host in '$tempDir'..."
        $buildOutput = & dotnet build (Join-Path $tempDir 'FoundryWebServer.csproj') `
            --configuration Release --nologo -v quiet 2>&1

        if ($LASTEXITCODE -ne 0) {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("dotnet build failed:`n$($buildOutput -join "`n")"),
                    'FoundryWebServerBuildFailed',
                    [System.Management.Automation.ErrorCategory]::InvalidResult,
                    $tempDir
                )
            )
            return
        }

        $exePath = Get-ChildItem -Path $tempDir -Recurse -Filter 'FoundryWebServer.exe' |
            Where-Object { $_.FullName -notlike '*\obj\*' } |
            Select-Object -First 1 -ExpandProperty FullName

        if (-not $exePath) {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Could not locate FoundryWebServer.exe after a successful build.'),
                    'FoundryWebServerExeNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $tempDir
                )
            )
            return
        }

        Write-Verbose "Launching $exePath"
        $psi = [System.Diagnostics.ProcessStartInfo]::new($exePath)
        $psi.UseShellExecute        = $false
        $psi.RedirectStandardOutput = $true
        $psi.CreateNoWindow         = $true
        $psi.ArgumentList.Add($ModelAlias)
        $psi.ArgumentList.Add([string]$Port)
        $psi.ArgumentList.Add($AppName)
        $psi.ArgumentList.Add($LogLevel)

        $proc = [System.Diagnostics.Process]::Start($psi)

        Write-Verbose "Waiting up to ${TimeoutSeconds}s for FOUNDRY_READY signal..."
        $readTask  = $proc.StandardOutput.ReadLineAsync()
        $completed = $readTask.Wait($TimeoutSeconds * 1000)

        if (-not $completed) {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("Timed out after ${TimeoutSeconds}s waiting for the Foundry web server to become ready."),
                    'FoundryWebServerStartTimeout',
                    [System.Management.Automation.ErrorCategory]::OperationTimeout,
                    $proc
                )
            )
            return
        }

        $readyLine = $readTask.Result

        if ($null -eq $readyLine) {
            $exitCode = if ($proc.HasExited) { $proc.ExitCode } else { '?' }
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("Foundry web server process exited before signalling ready (exit code: $exitCode). Check stderr for details."),
                    'FoundryWebServerStartFailed',
                    [System.Management.Automation.ErrorCategory]::InvalidResult,
                    $proc
                )
            )
            return
        }

        if ($readyLine -notmatch '^FOUNDRY_READY endpoint=(\S+) model=(\S+)') {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("Unexpected output from Foundry web server: '$readyLine'"),
                    'FoundryWebServerUnexpectedOutput',
                    [System.Management.Automation.ErrorCategory]::InvalidResult,
                    $proc
                )
            )
            return
        }

        $endpoint = $Matches[1]
        $modelId  = $Matches[2]

        $script:FoundryWebServerProcess  = $proc
        $script:FoundryWebServerEndpoint = $endpoint
        $script:FoundryWebServerModelId  = $modelId
        $script:FoundryWebServerTempDir  = $tempDir
        $started = $true

        Write-Verbose "Foundry web server ready at $endpoint (model: $modelId, PID: $($proc.Id))"

        return [PSCustomObject]@{
            Endpoint  = $endpoint
            ModelId   = $modelId
            Port      = $Port
            ProcessId = $proc.Id
        }
    }
    finally {
        if (-not $started) {
            if ($null -ne $proc -and -not $proc.HasExited) {
                try { $proc.Kill($true) } catch { }
            }
            if (Test-Path $tempDir) {
                Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
            }
        }
    }
}
