# pwsh-foundry

**PwshFoundry** is a PowerShell module (v0.2.0, alpha) that wraps the [Microsoft Foundry Local](https://github.com/microsoft/foundry-local) CLI and REST API so that PowerShell users and automation scripts can interact with local AI workloads without dropping into raw `afoundry` commands or hand-crafting HTTP requests.

> **Alpha notice** — the API surface is unstable and breaking changes may occur between releases.

> **CLI version notice** — some cmdlets (e.g. `New-FoundryAudioTranscription`) require features only available in Foundry Local v1.1.1 or later, which must be installed manually. The version distributed via `winget` / `brew` auto-install may not include these features. Check `Get-FoundryVersion` and refer to the per-cmdlet notes for version requirements.

---

## Requirements

| Requirement | Version |
|---|---|
| PowerShell | 7.4 or later |
| Foundry Local CLI | 0.10.0 or later *(optional — see SDK mode below)* |
| .NET SDK | 8.0 or later *(required by `Start-FoundryWebServer`; also required by `Get-FoundryModelList` and `New-FoundryChat` when the CLI is absent)* |
| Pester *(tests only)* | 5.x |
| PSScriptAnalyzer *(build only)* | latest |

> **API version notice** — Foundry Local CLI **0.10.1** (SDK version **1.20**) changed several REST endpoint paths.
> The module detects the version automatically and routes requests to the correct URI.
> See [API endpoint changes (v0.10.0)](doc/README.md#api-endpoint-changes-v0100) for the full mapping.

> **SDK mode** — when the Foundry Local CLI is not installed, the module falls back to the Azure AI Foundry Local .NET SDK for operations that support it (`Get-FoundryModelList`, `New-FoundryChat`).
> The .NET 8 SDK (`dotnet` on `PATH`) must be available in this case.
> `Get-FoundryVersion` returns `Source = 'SDK'` to indicate this mode.

---

## Installing Foundry Local

**Windows**
```powershell
winget install Microsoft.FoundryLocal
```

**macOS**
```bash
brew install microsoft/foundrylocal/foundrylocal
```

---

## Installing the module

```powershell
# Import locally from the repo
Import-Module ./src/PwshFoundry/PwshFoundry.psd1 -Force
```

---

## Quick start

```powershell
Import-Module ./src/PwshFoundry/PwshFoundry.psd1 -Force

# Check the CLI version (or detect SDK mode)
Get-FoundryVersion

# List all models available in the Foundry catalogue
Get-FoundryModelList

# List models already downloaded to the local cache
Get-FoundryModelCache

# Send a chat request — the model is loaded automatically if not already running
$msg    = New-FoundryMessage -UserPrompt 'Explain quantum computing in plain English'
$result = New-FoundryChat -Message $msg -Model 'qwen2.5-0.5b-instruct-generic-cpu'
$result.message.content
```

---

## Cmdlet reference

The full per-cmdlet reference (parameters, examples, return objects) has moved to [`doc/README.md`](doc/README.md).

The module exports the following cmdlets — see [`doc/README.md`](doc/README.md) for details on each:

- [`Get-FoundryVersion`](doc/README.md#get-foundryversion)
- [`Get-FoundryModelList`](doc/README.md#get-foundrymodellist)
- [`Get-FoundryModelCache`](doc/README.md#get-foundrymodelcache)
- [`New-FoundryMessage`](doc/README.md#new-foundrymessage)
- [`New-FoundryChatContext`](doc/README.md#new-foundrychatcontext)
- [`New-FoundryTool`](doc/README.md#new-foundrytool)
- [`Get-FoundryStatus`](doc/README.md#get-foundrystatus)
- [`Start-FoundryWebServer`](doc/README.md#start-foundrywebserver)
- [`Stop-FoundryWebServer`](doc/README.md#stop-foundrywebserver)
- [`Save-FoundryModel`](doc/README.md#save-foundrymodel)
- [`New-FoundryChat`](doc/README.md#new-foundrychat)
- [`New-FoundryAudioTranscription`](doc/README.md#new-foundryaudiotranscription)
- [`New-FoundryEmbedding`](doc/README.md#new-foundryembedding)
- [`Compare-FoundryEmbedding`](doc/README.md#compare-foundryembedding)

The [API endpoint changes (v0.10.0)](doc/README.md#api-endpoint-changes-v0100) mapping also lives in `doc/README.md`.

---

## Samples

The [`samples/`](samples/) directory has runnable scripts demonstrating common usage patterns, including an interactive chat REPL (`interactive-chat.ps1`), a function-calling demo (`tool-calling-demo.ps1`), and a semantic-search demo built on embeddings (`embedding-search.ps1`). See [`samples/README.md`](samples/README.md) for the full list.

For a longer worked example, [`samples/rag/`](samples/rag/) builds a complete **Retrieval-Augmented Generation** pipeline out of `New-FoundryEmbedding`, `Compare-FoundryEmbedding` and `New-FoundryChat`: it chunks and embeds a document corpus into a vector index, retrieves the passages relevant to a question, and has the model answer from them with citations. Each stage prints what it is doing, and [`samples/rag/README.md`](samples/rag/README.md) explains the design and what a production system would do differently.

---

## Build and test

```powershell
# Run all unit tests
Invoke-Pester ./tests/ -Output Detailed

# Full build (lint + test + package)
./build/build.ps1
```

Integration tests (require a running Foundry service) are tagged `-Tag Integration` and excluded from CI by default:

```powershell
Invoke-Pester ./tests/Integration/ -Tag Integration
```

---

## License

© Olivier Miossec. All rights reserved. See [LICENSE](LICENSE).
