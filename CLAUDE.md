# CLAUDE.md — pwsh-foundry

## Project purpose

PowerShell module (`PwshFoundry`) that wraps the **Azure AI Foundry local CLI** and the **Azure AI Foundry local SDK for .NET** so that PowerShell users and automation scripts can interact with local Foundry workloads without dropping into raw `dotnet` or `afoundry` commands.

## Repository layout

```
pwsh-foundry/
├── src/PwshFoundry/
│   ├── PwshFoundry.psd1      # Module manifest (version, exports, metadata)
│   ├── PwshFoundry.psm1      # Dot-sources Public/ and Private/; manages module state
│   ├── Public/               # One file per exported function (Verb-Noun.ps1)
│   ├── Private/              # Internal helpers, not exported
│   └── Classes/              # PowerShell classes / enums used across the module
├── tests/                    # Pester v5 tests mirroring src/PwshFoundry/
├── build/
│   └── build.ps1             # Build, test, and package script
├── .claude/                  # Claude Code configuration (skills, agents)
├── .gitignore
├── LICENSE
└── README.md
```

## Module conventions

- **Function naming**: standard PowerShell `Verb-Noun` with the noun prefix `Foundry` (e.g. `Get-FoundryModel`, `Start-FoundryAgent`).
- **Approved verbs only**: run `Get-Verb` to verify before adding a new function.
- **One public function per file**: filename must match the function name exactly (`Get-FoundryModel.ps1`).
- **Private helpers**: prefix the function name with an underscore-free convention — use descriptive internal names and keep them in `Private/`.
- **No aliases inside the module**: define them in the manifest's `AliasesToExport` only if explicitly needed.
- **Error handling**: use `$PSCmdlet.ThrowTerminatingError()` for fatal errors; `Write-Error` for non-fatal. Never swallow exceptions silently.
- **Output**: emit objects, not formatted strings. Callers format; the module delivers data.
- **[CmdletBinding()]**: every public function must declare it and include `param()`.

## Foundry CLI integration

The module shells out to the Foundry CLI (`afoundry` / `foundry`). Key rules:

- Detect CLI presence with a private helper `Test-FoundryCli`; throw a clear error if missing.
- Capture stdout/stderr separately; surface stderr as `Write-Warning` or `Write-Error` depending on exit code.
- Never hard-code CLI paths — resolve via `Get-Command` or a configurable module variable `$script:FoundryCliBin`.
- Parse JSON output where the CLI supports `--output json`; avoid screen-scraping text output.

## Foundry SDK (.NET) integration

The module can also invoke the Foundry SDK via `dotnet` run-to-completion or `Add-Type` loaded assemblies:

- SDK assembly path is configurable; default discovery looks in the standard NuGet local cache.
- Wrap SDK calls in `try/catch` translating .NET exceptions into PowerShell `ErrorRecord` objects.

## Build and test

```powershell
# Run all Pester tests
Invoke-Pester ./tests/ -Output Detailed

# Build (lint + test + create .nupkg in ./build/output/)
./build/build.ps1

# Import module locally for manual testing
Import-Module ./src/PwshFoundry/PwshFoundry.psd1 -Force
```

Requirements: **PowerShell 7.4+**, **Pester 5.x**, **PSScriptAnalyzer** (for build lint step).

## Testing guidelines

- Use **Pester 5** (`BeforeAll`, `AfterAll`, `Should -Be`, `Should -Throw`).
- Mock `Invoke-Expression` / `Start-Process` / `Get-Command` to avoid real CLI calls in unit tests.
- Integration tests (require real CLI) live in `tests/Integration/` and are tagged `-Tag Integration`; they are excluded from CI by default.
- Test file names: `<FunctionName>.Tests.ps1` in `tests/`.

## Code style

- 4-space indentation, no tabs.
- Keep lines under 120 characters.
- Use `[Parameter(Mandatory)]` (no `= $true`).
- Prefer `[ValidateSet(...)]` over manual `if` guards for constrained string params.
- Run **PSScriptAnalyzer** with default rules before committing; fix all warnings.

## Git workflow

- Branch from `main`; use short descriptive branch names (`feat/get-foundry-model`).
- Commit messages: imperative mood, ≤ 72 chars subject (`Add Get-FoundryModel cmdlet`).
- No direct commits to `main`.
