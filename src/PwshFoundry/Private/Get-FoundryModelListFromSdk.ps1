#Requires -Version 7.4

function Get-FoundryModelListFromSdk {
    <#
    .SYNOPSIS
        Lists catalog models via the Azure AI Foundry Local SDK.
    .DESCRIPTION
        Compiles and runs a minimal .NET host that calls the Microsoft.AI.Foundry.Local
        SDK catalog API and emits the model list as JSON, projected to the same shape
        as the Foundry CLI's 'model list --output json' output. The compiled host is
        cached in the module state so repeated calls skip the build step.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter()]
        [string]$AppName = 'pwsh_foundry'
    )

    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("The 'dotnet' CLI was not found on PATH. Install the .NET SDK from https://dot.net"),
                'DotNetSdkNotFound',
                [System.Management.Automation.ErrorCategory]::NotInstalled,
                'dotnet'
            )
        )
    }

    if (-not ($script:FoundryModelListSdkExe -and (Test-Path $script:FoundryModelListSdkExe))) {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "FoundryModelList_$(New-Guid)"
        $null = New-Item -ItemType Directory -Path $tempDir -ErrorAction Stop

        $programCs = @'
using Microsoft.AI.Foundry.Local;
using Microsoft.Extensions.Logging.Abstractions;
using System.Text.Json;

var appName = args.Length > 0 ? args[0] : "pwsh_foundry";

var config = new Configuration
{
    AppName  = appName,
    LogLevel = Microsoft.AI.Foundry.Local.LogLevel.Warning
};

await FoundryLocalManager.CreateAsync(config, NullLogger.Instance);
var mgr     = FoundryLocalManager.Instance;
var catalog = await mgr.GetCatalogAsync();
var models  = await catalog.ListModelsAsync();

// Match the vocabulary of 'foundry model list --output json'.
static string MapTask(string? task) => task switch
{
    "chat-completion"              => "Chat",
    "embeddings"                   => "Embedding",
    "vision-language-chat"         => "Multimodal",
    "automatic-speech-recognition" => "Speech",
    _                              => task ?? string.Empty
};

static string MapDevice(string? device) =>
    string.IsNullOrEmpty(device)
        ? string.Empty
        : char.ToUpperInvariant(device[0]) + device.Substring(1).ToLowerInvariant();

var projected = models
    .SelectMany(m => m.Variants.Count > 0 ? m.Variants.AsEnumerable() : Enumerable.Repeat(m, 1))
    .Select(v => v.Info)
    .Select(i => new
    {
        alias               = i.Alias,
        id                  = i.Id,
        displayName         = i.DisplayName,
        type                = MapTask(i.Task),
        device              = MapDevice(i.Runtime?.DeviceType.ToString()),
        fileSizeMb          = i.FileSizeMb,
        cached              = i.Cached,
        license             = i.License,
        supportsToolCalling = i.SupportsToolCalling
    });

Console.WriteLine("FOUNDRY_MODELS " + JsonSerializer.Serialize(projected));
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

        Set-Content -Path (Join-Path $tempDir 'Program.cs')               -Value $programCs -Encoding utf8
        Set-Content -Path (Join-Path $tempDir 'FoundryModelList.csproj') -Value $csproj    -Encoding utf8

        Write-Verbose "Building Foundry model-list host in '$tempDir'..."
        $buildOutput = & dotnet build (Join-Path $tempDir 'FoundryModelList.csproj') `
            --configuration Release --nologo -v quiet 2>&1

        if ($LASTEXITCODE -ne 0) {
            Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("dotnet build failed:`n$($buildOutput -join "`n")"),
                    'FoundryModelListBuildFailed',
                    [System.Management.Automation.ErrorCategory]::InvalidResult,
                    $tempDir
                )
            )
        }

        $exePath = Get-ChildItem -Path $tempDir -Recurse -Filter 'FoundryModelList.exe' |
            Where-Object { $_.FullName -notlike '*\obj\*' } |
            Select-Object -First 1 -ExpandProperty FullName

        if (-not $exePath) {
            Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Could not locate FoundryModelList.exe after a successful build.'),
                    'FoundryModelListExeNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $tempDir
                )
            )
        }

        $script:FoundryModelListSdkExe     = $exePath
        $script:FoundryModelListSdkTempDir = $tempDir
    }

    Write-Verbose "Running $script:FoundryModelListSdkExe"
    $output = & $script:FoundryModelListSdkExe $AppName 2>&1
    $stdout = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
    $stderr = @($output | Where-Object { $_ -is  [System.Management.Automation.ErrorRecord] })

    if ($LASTEXITCODE -ne 0) {
        $msg = ($stderr | Out-String).Trim()
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("Foundry SDK model-list host exited $LASTEXITCODE : $msg"),
                'FoundryModelListSdkError',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $script:FoundryModelListSdkExe
            )
        )
    }

    $resultLine = $stdout | Where-Object { $_ -like 'FOUNDRY_MODELS *' } | Select-Object -First 1

    if (-not $resultLine) {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("Unexpected output from Foundry SDK model-list host: '$($stdout -join "`n")'"),
                'FoundryModelListSdkUnexpectedOutput',
                [System.Management.Automation.ErrorCategory]::InvalidResult,
                $script:FoundryModelListSdkExe
            )
        )
    }

    return @(($resultLine -replace '^FOUNDRY_MODELS ', '') | ConvertFrom-Json)
}
