#Requires -Version 7.4
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' },
#          @{ ModuleName='PSScriptAnalyzer'; ModuleVersion='1.0' }

[CmdletBinding()]
param(
    [ValidateSet('Lint', 'Test', 'Package', 'All')]
    [string]$Task = 'All'
)

$ErrorActionPreference = 'Stop'
$root      = Split-Path $PSScriptRoot -Parent
$srcRoot   = Join-Path $root 'src/PwshFoundry'
$outDir    = Join-Path $PSScriptRoot 'output'

function Invoke-Lint {
    Write-Host '--- PSScriptAnalyzer ---' -ForegroundColor Cyan
    $results = Invoke-ScriptAnalyzer -Path $srcRoot -Recurse -Severity Warning, Error
    if ($results) {
        $results | Format-Table -AutoSize
        throw "PSScriptAnalyzer found $($results.Count) issue(s)."
    }
    Write-Host 'Lint: OK' -ForegroundColor Green
}

function Invoke-Tests {
    Write-Host '--- Pester ---' -ForegroundColor Cyan
    $config = New-PesterConfiguration
    $config.Run.Path            = Join-Path $root 'tests'
    $config.Filter.ExcludeTag   = 'Integration'
    $config.Output.Verbosity    = 'Detailed'
    $config.TestResult.Enabled  = $true
    $config.TestResult.OutputPath = Join-Path $outDir 'TestResults.xml'
    $result = Invoke-Pester -Configuration $config
    if ($result.FailedCount -gt 0) { throw "Pester: $($result.FailedCount) test(s) failed." }
    Write-Host 'Tests: OK' -ForegroundColor Green
}

function Invoke-Package {
    Write-Host '--- Package ---' -ForegroundColor Cyan
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory $outDir | Out-Null }
    $manifest = Import-PowerShellDataFile "$srcRoot/PwshFoundry.psd1"
    $version   = $manifest.ModuleVersion
    Compress-Archive -Path $srcRoot -DestinationPath (Join-Path $outDir "PwshFoundry-$version.zip") -Force
    Write-Host "Package: PwshFoundry-$version.zip written to $outDir" -ForegroundColor Green
}

switch ($Task) {
    'Lint'    { Invoke-Lint }
    'Test'    { Invoke-Tests }
    'Package' { Invoke-Package }
    'All'     { Invoke-Lint; Invoke-Tests; Invoke-Package }
}
