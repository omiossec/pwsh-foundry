--- 
name: powershell-module 
description: conventions and guidelines for building PowerShell modules
argument-hint: "[check|fix]" 
--- 


# PowerShell Module Skill

This skill provides guidance and conventions for building PowerShell modules.

## When to use this skill

Use this skill when:
- Writing new PowerShell modules
- Reviewing existing PowerShell module code for quality issues
- Asked to audit, refactor, or improve PowerShell modules
    
## Trigger

Use this skill when the user asks to:
- Create or modify a PowerShell function (public or private)
- Create or modify a PowerShell class
- Write or update Pester tests
- Scaffold new module files or structure

## Conventions

### write-verbose?/write-debug?
- Use `Write-Verbose` for informational messages that may be helpful for debugging but are not critical to the user, only visible when the `-Verbose` switch is used. 
- Use `Write-Debug` for detailed debugging information that is typically only relevant when troubleshooting specific issues. This can be enabled with the `-Debug` switch when running the function.
- Avoid using `Write-Host` for regular output; reserve it for special cases where you want to display colored or formatted output directly to the console. For standard output, return objects or use `Write-Output`.

### psm1 file 
- The `.psm1` file should contain all individual functions and class files, and the `Export-ModuleMember` call to specify which public functions are exported. The build script will handle the creation of the `.psm1` manifest file, so you do not need to create that manually.
- All actual code (functions, classes) should live in separate `.ps1` files under the `src/` directory, organized into `Public`, `Private`, and `Classes` subdirectories.

### Naming
- **Variables / Parameters:** camelCase — `$issueTitle`, `$repoOwner`
- **Functions:** Approved verb + PascalCase noun — `Get-GtIssue`, `New-GtIssue`
- **Classes:** PascalCase — `GitHubIssue`
- **Files:** one function/class per file, filename matches the function/class name

### Function Template (Public)

```powershell
#Requires -Version 7.0

<#
.SYNOPSIS
    One-line summary.
.DESCRIPTION
    Full description.
.PARAMETER paramName
    Description of parameter.
.EXAMPLE
    Verb-Noun -param value
#>
function Verb-GtNoun {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$paramName
    )

    process {
        # implementation
    }
}
```

### Function Template (Private)

Same as public but omit `SupportsShouldProcess` unless needed. No export.

### Class Template

```powershell
class ClassName {
    [string] $PropertyOne = ''
    [int]    $PropertyTwo = 0

    ClassName() {}

    ClassName([string]$propertyOne) {
        $this.PropertyOne = $propertyOne
    }
}
```

### Module Root (`<ModuleName>.psm1`) Dot-Source Order

1. `src/Classes/*.ps1`
2. `src/Private/*.ps1`
3. `src/Public/*.ps1`

### API Calls

- Always go through `Invoke-GtApiRequest` (private helper)
- Use `Invoke-RestMethod` — never `curl` or `wget`
- Set `$ErrorActionPreference = 'Stop'` and wrap in `try/catch`

### Pester Tests

- File: `tests/Unit/<Public|Private>/<FunctionName>.Tests.ps1`
- Mock all HTTP calls with `Mock -ModuleName psGTIssue Invoke-GtApiRequest`
- Cover: happy path, property mapping, API error, parameter validation
- Use `BeforeAll` to import the module; `BeforeEach` for per-test mocks

```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../../src/<ModuleName>.psm1') -Force
}

Describe 'Verb-GtNoun' {
    Context 'success' {
        BeforeEach {
            Mock -ModuleName psGTIssue Invoke-GtApiRequest { return $mockResponse }
        }
        It 'returns expected object' { ... }
    }
}
```

## File Placement Checklist

| Artifact | Path |
|---|---|
| Public function | `src/Public/<FunctionName>.ps1` |
| Private function | `src/Private/<FunctionName>.ps1` |
| Class | `src/Classes/<ClassName>.ps1` |
| Unit test | `tests/Unit/Public/<FunctionName>.Tests.ps1` |
| Module manifest | `build/psGTIssue.psd1` |
