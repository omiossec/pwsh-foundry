#Requires -Version 7.4

<#
.SYNOPSIS
    Builds, verifies, and packages the PwshFoundry module.
.DESCRIPTION
    Assembles every Classes/, Private/ and Public/ script under src/PwshFoundry into a single
    PwshFoundry.psm1, generates the matching manifest, and packages the result.

    Tasks:
      Clean    - remove build/output
      Analyze  - run PSScriptAnalyzer on the source (fails on Warning/Error)
      Test     - run the Pester unit tests (Integration tag excluded)
      Build    - assemble build/output/PwshFoundry (single .psm1 + .psd1)
      Verify   - import the built module in a clean pwsh process and check its exports
      Package  - create PwshFoundry-<version>.zip and PwshFoundry.<version>.nupkg
      All      - Clean, Analyze, Test, Build, Verify, Package
      Release  - Clean, Build, Verify, Package (no quality gate; used by CI)
.PARAMETER Task
    One or more tasks to run, in the order given.
.PARAMETER Version
    Module version to stamp into the built manifest (e.g. 1.2.0 or 1.2.0-preview1).
    Defaults to ModuleVersion from the source manifest. A leading 'v' is accepted.
.EXAMPLE
    ./build/build.ps1 -Task Build, Verify
.EXAMPLE
    ./build/build.ps1 -Task Release -Version v0.3.0
#>
[CmdletBinding()]
param(
    [ValidateSet('Clean', 'Analyze', 'Test', 'Build', 'Verify', 'Package', 'All', 'Release')]
    [string[]]$Task = 'All',

    [string]$Version
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$moduleName   = 'PwshFoundry'
$root         = Split-Path $PSScriptRoot -Parent
$srcRoot      = Join-Path $root "src/$moduleName"
$outDir       = Join-Path $PSScriptRoot 'output'
$moduleOutDir = Join-Path $outDir $moduleName
$sourceFolders = @('Classes', 'Private', 'Public')

function Get-BuildVersion {
    $manifestVersion = (Import-PowerShellDataFile (Join-Path $srcRoot "$moduleName.psd1")).ModuleVersion
    $raw = if ($Version) { $Version.TrimStart('v', 'V') } else { $manifestVersion }

    if ($raw -notmatch '^(?<core>\d+\.\d+\.\d+)(-(?<pre>[0-9A-Za-z]+))?$') {
        throw "Invalid version '$raw'. Expected MAJOR.MINOR.PATCH with an optional -prerelease suffix."
    }
    if ($Version -and $Matches.core -ne $manifestVersion) {
        Write-Warning "Build version $($Matches.core) differs from source manifest version $manifestVersion."
    }

    [PSCustomObject]@{
        Full       = $raw
        Core       = $Matches.core
        Prerelease = $Matches['pre']
    }
}

function Assert-ModuleAvailable {
    param([string]$Name, [version]$MinimumVersion)

    $found = Get-Module -ListAvailable -Name $Name | Where-Object Version -GE $MinimumVersion
    if (-not $found) {
        throw "$Name $MinimumVersion or later is required. Install it with: Install-PSResource $Name"
    }
}

# Returns the script text with #Requires lines removed. Uses the tokenizer so that
# here-strings (e.g. embedded C# 'using' directives) are never touched.
function Get-ScriptBody {
    param([string]$Path)

    $tokens = $null
    $errors = $null
    $content = Get-Content -LiteralPath $Path -Raw
    [void][System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$tokens, [ref]$errors)
    if ($errors) {
        throw "Parse error in ${Path}: $($errors[0].Message) (line $($errors[0].Extent.StartLineNumber))"
    }

    $requires = $tokens | Where-Object {
        $_.Kind -eq 'Comment' -and $_.Text -match '^#requires\s'
    } | Sort-Object { $_.Extent.StartOffset } -Descending

    foreach ($token in $requires) {
        $content = $content.Remove($token.Extent.StartOffset, $token.Extent.EndOffset - $token.Extent.StartOffset)
    }
    $content.Trim()
}

# Module-scope state from the source .psm1: every top-level statement except the dot-source loop.
function Get-ModuleStateBlock {
    $psm1 = Join-Path $srcRoot "$moduleName.psm1"
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($psm1, [ref]$null, [ref]$null)

    $ast.EndBlock.Statements |
        Where-Object { $_ -isnot [System.Management.Automation.Language.ForEachStatementAst] } |
        ForEach-Object { $_.Extent.Text }
}

function Invoke-Clean {
    Write-Host '--- Clean ---' -ForegroundColor Cyan
    if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
    Write-Host 'Clean: OK' -ForegroundColor Green
}

function Invoke-Analyze {
    Write-Host '--- PSScriptAnalyzer ---' -ForegroundColor Cyan
    Assert-ModuleAvailable -Name PSScriptAnalyzer -MinimumVersion 1.0
    $results = Invoke-ScriptAnalyzer -Path $srcRoot -Recurse -Severity Warning, Error
    if ($results) {
        $results | Format-Table RuleName, Severity, ScriptName, Line, Message -AutoSize | Out-String -Width 200 |
            Write-Host
        throw "PSScriptAnalyzer found $(@($results).Count) issue(s)."
    }
    Write-Host 'Analyze: OK' -ForegroundColor Green
}

function Invoke-Test {
    Write-Host '--- Pester ---' -ForegroundColor Cyan
    Assert-ModuleAvailable -Name Pester -MinimumVersion 5.0
    Import-Module Pester -MinimumVersion 5.0

    New-Item -ItemType Directory $outDir -Force | Out-Null
    $config = New-PesterConfiguration
    $config.Run.Path              = Join-Path $root 'tests'
    $config.Run.PassThru          = $true
    $config.Filter.ExcludeTag     = 'Integration'
    $config.Output.Verbosity      = 'Detailed'
    $config.TestResult.Enabled    = $true
    $config.TestResult.OutputPath = Join-Path $outDir 'TestResults.xml'
    $result = Invoke-Pester -Configuration $config
    if ($result.FailedCount -gt 0) { throw "Pester: $($result.FailedCount) test(s) failed." }
    Write-Host 'Test: OK' -ForegroundColor Green
}

function Invoke-Build {
    Write-Host '--- Build ---' -ForegroundColor Cyan
    $buildVersion = Get-BuildVersion

    if (Test-Path $moduleOutDir) { Remove-Item $moduleOutDir -Recurse -Force }
    New-Item -ItemType Directory $moduleOutDir -Force | Out-Null

    $publicFunctions = [System.Collections.Generic.List[string]]::new()
    $seenFunctions   = @{}
    $sb = [System.Text.StringBuilder]::new()

    [void]$sb.AppendLine('#Requires -Version 7.4')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("# $moduleName $($buildVersion.Full)")
    [void]$sb.AppendLine('# Generated by build/build.ps1 - do not edit. Edit the sources in src/PwshFoundry instead.')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('#region Module state')
    Get-ModuleStateBlock | ForEach-Object { [void]$sb.AppendLine($_) }
    [void]$sb.AppendLine('#endregion Module state')

    foreach ($folder in $sourceFolders) {
        $files = Get-ChildItem -Path (Join-Path $srcRoot $folder) -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
            Sort-Object Name

        foreach ($file in $files) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
            $functions = $ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                    $node.Parent -eq $ast.EndBlock
                }, $false)

            foreach ($function in $functions) {
                if ($seenFunctions.ContainsKey($function.Name)) {
                    throw "Function '$($function.Name)' is defined in both " +
                        "$($seenFunctions[$function.Name]) and $folder/$($file.Name)."
                }
                $seenFunctions[$function.Name] = "$folder/$($file.Name)"
            }

            if ($folder -eq 'Public') {
                if ($functions.Name -notcontains $file.BaseName) {
                    throw "Public/$($file.Name) must define a function named '$($file.BaseName)'."
                }
                $publicFunctions.Add($file.BaseName)
            }

            [void]$sb.AppendLine()
            [void]$sb.AppendLine("#region $folder/$($file.Name)")
            [void]$sb.AppendLine((Get-ScriptBody -Path $file.FullName))
            [void]$sb.AppendLine("#endregion $folder/$($file.Name)")
        }
    }

    [void]$sb.AppendLine()
    [void]$sb.AppendLine('Export-ModuleMember -Function @(')
    [void]$sb.AppendLine(($publicFunctions | ForEach-Object { "    '$_'" }) -join ",`n")
    [void]$sb.AppendLine(')')

    $psm1Path = Join-Path $moduleOutDir "$moduleName.psm1"
    Set-Content -LiteralPath $psm1Path -Value $sb.ToString() -Encoding utf8BOM -NoNewline

    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($psm1Path, [ref]$null, [ref]$parseErrors)
    if ($parseErrors) {
        throw "Built $moduleName.psm1 does not parse: $($parseErrors[0].Message) " +
            "(line $($parseErrors[0].Extent.StartLineNumber))"
    }

    # Manifest: stamp the version and export exactly the public functions found.
    $manifest = Get-Content -LiteralPath (Join-Path $srcRoot "$moduleName.psd1") -Raw
    $exportList = "FunctionsToExport = @(`n" + (($publicFunctions | ForEach-Object { "    '$_'" }) -join ",`n") + "`n)"
    $manifest = $manifest -replace "(?m)^ModuleVersion\s*=\s*'[^']*'", "ModuleVersion = '$($buildVersion.Core)'"
    $manifest = $manifest -replace '(?s)FunctionsToExport\s*=\s*@\([^)]*\)', $exportList
    if ($buildVersion.Prerelease) {
        $manifest = $manifest -replace "(?m)^(\s*)#?\s*Prerelease\s*=\s*'[^']*'",
            "`${1}Prerelease = '$($buildVersion.Prerelease)'"
    }

    $psd1Path = Join-Path $moduleOutDir "$moduleName.psd1"
    Set-Content -LiteralPath $psd1Path -Value $manifest -Encoding utf8BOM -NoNewline
    [void](Test-ModuleManifest -Path $psd1Path)

    foreach ($extra in 'LICENSE', 'README.md') {
        $extraPath = Join-Path $root $extra
        if (Test-Path $extraPath) { Copy-Item $extraPath $moduleOutDir }
    }

    Write-Host ("Build: {0} {1} -> {2} ({3} public functions)" -f
        $moduleName, $buildVersion.Full, $moduleOutDir, $publicFunctions.Count) -ForegroundColor Green
}

function Invoke-Verify {
    Write-Host '--- Verify ---' -ForegroundColor Cyan
    $psd1Path = Join-Path $moduleOutDir "$moduleName.psd1"
    if (-not (Test-Path $psd1Path)) { throw "Built module not found at $psd1Path. Run the Build task first." }

    # A child process avoids clashing with class types already loaded from the source module.
    $script = {
        param($manifestPath)
        $ErrorActionPreference = 'Stop'
        $module = Import-Module $manifestPath -PassThru -Force
        $expected = (Import-PowerShellDataFile $manifestPath).FunctionsToExport
        $actual   = @($module.ExportedFunctions.Keys)

        $missing = $expected | Where-Object { $_ -notin $actual }
        $extra   = $actual | Where-Object { $_ -notin $expected }
        if ($missing) { throw "Functions not exported: $($missing -join ', ')" }
        if ($extra)   { throw "Unexpected exported functions: $($extra -join ', ')" }

        # Exercise the module classes through their public factory functions.
        $message = New-FoundryMessage -UserPrompt 'build verification'
        if ($message.GetType().Name -ne 'FoundryMessage') { throw 'New-FoundryMessage did not return a FoundryMessage.' }
        $context = New-FoundryChatContext -UserPrompt 'build verification'
        if ($context.GetType().Name -ne 'FoundryChatContext') {
            throw 'New-FoundryChatContext did not return a FoundryChatContext.'
        }

        "Verified $($actual.Count) exported functions from $($module.Name) $($module.Version)"
    }

    $pwsh = (Get-Process -Id $PID).Path
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes(
            "& { $script } '$($psd1Path -replace "'", "''")'"))
    & $pwsh -NoProfile -NonInteractive -EncodedCommand $encoded
    if ($LASTEXITCODE -ne 0) { throw "Verify: built module failed verification (exit code $LASTEXITCODE)." }
    Write-Host 'Verify: OK' -ForegroundColor Green
}

function Invoke-Package {
    Write-Host '--- Package ---' -ForegroundColor Cyan
    $psd1Path = Join-Path $moduleOutDir "$moduleName.psd1"
    if (-not (Test-Path $psd1Path)) { throw "Built module not found at $psd1Path. Run the Build task first." }
    $buildVersion = Get-BuildVersion

    $zipPath = Join-Path $outDir "$moduleName-$($buildVersion.Full).zip"
    Compress-Archive -Path $moduleOutDir -DestinationPath $zipPath -Force
    Write-Host "Package: $zipPath" -ForegroundColor Green

    # .nupkg via a temporary local PSResourceGet repository (installable with Install-PSResource).
    $repoName = "$moduleName-build-output"
    $nupkgDir = Join-Path $outDir 'nupkg'
    New-Item -ItemType Directory $nupkgDir -Force | Out-Null
    try {
        Register-PSResourceRepository -Name $repoName -Uri $nupkgDir -Trusted -Force
        Publish-PSResource -Path $moduleOutDir -Repository $repoName -SkipDependenciesCheck
    } finally {
        Unregister-PSResourceRepository -Name $repoName -ErrorAction SilentlyContinue
    }
    Get-ChildItem $nupkgDir -Filter '*.nupkg' | ForEach-Object {
        Move-Item $_.FullName $outDir -Force
        Write-Host "Package: $(Join-Path $outDir $_.Name)" -ForegroundColor Green
    }
    Remove-Item $nupkgDir -Recurse -Force
}

$expanded = foreach ($t in $Task) {
    switch ($t) {
        'All'     { 'Clean', 'Analyze', 'Test', 'Build', 'Verify', 'Package' }
        'Release' { 'Clean', 'Build', 'Verify', 'Package' }
        default   { $t }
    }
}

foreach ($t in $expanded) {
    switch ($t) {
        'Clean'   { Invoke-Clean }
        'Analyze' { Invoke-Analyze }
        'Test'    { Invoke-Test }
        'Build'   { Invoke-Build }
        'Verify'  { Invoke-Verify }
        'Package' { Invoke-Package }
    }
}
