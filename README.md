# pwsh-foundry

**PwshFoundry** is a PowerShell module (v0.1.0, alpha) that wraps the [Microsoft Foundry Local](https://github.com/microsoft/foundry-local) CLI and REST API so that PowerShell users and automation scripts can interact with local AI workloads without dropping into raw `afoundry` commands or hand-crafting HTTP requests.

> **Alpha notice** — the API surface is unstable and breaking changes may occur between releases.

---

## Requirements

| Requirement | Version |
|---|---|
| PowerShell | 7.4 or later |
| Foundry Local CLI | latest preview |
| Pester *(tests only)* | 5.x |
| PSScriptAnalyzer *(build only)* | latest |

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

# Check the CLI version
Get-FoundryVersion

# List all models available in the Foundry catalogue
Get-FoundryModelList

# List models already downloaded to the local cache
Get-FoundryModelCache

# Send a chat request
$msg    = New-FoundryMessage -UserPrompt 'Explain quantum computing in plain English'
$result = New-FoundryChat -Message $msg -Model 'phi-3-mini-128k-instruct-qnn-npu:3'
$result.message.content
```

---

## Cmdlet reference

### `Get-FoundryVersion`

Returns the installed Foundry CLI version string.

```powershell
Get-FoundryVersion
```

---

### `Get-FoundryModelList`

Queries the Foundry local service for the full model catalogue (downloaded or not).
Starts the service automatically if it is not running.

```powershell
Get-FoundryModelList
```

Returns objects with properties: `name`, `displayName`, `providerType`, `version`, `promptTemplate`, `publisher`, `task`, `deviceType`, `maxOutputTokens`.

---

### `Get-FoundryModelCache`

Lists models that have already been downloaded to the local cache.

```powershell
Get-FoundryModelCache
```

---

### `New-FoundryMessage`

Creates a `FoundryMessage` object that holds the user prompt and an optional system prompt.

```powershell
# User prompt only — default system prompt is used
$msg = New-FoundryMessage -UserPrompt 'What is the capital of France?'

# With a custom system prompt
$msg = New-FoundryMessage -UserPrompt 'What is the capital of France?' `
                          -SystemPrompt 'You are a geography teacher.'
```

| Parameter | Type | Required | Description |
|---|---|---|---|
| `UserPrompt` | `string` | Yes | The user turn content. |
| `SystemPrompt` | `string` | No | Overrides the default system prompt (`You are a helpful assistant`). |

---

### `New-FoundryChat`

Sends a chat completion request to the local Foundry service and returns a mapped result object.

```powershell
$msg    = New-FoundryMessage -UserPrompt 'Write a haiku about PowerShell'
$result = New-FoundryChat -Message $msg -Model 'phi-3-mini-128k-instruct-qnn-npu:3'

$result.message.content   # assistant reply text
$result.model             # model that handled the request
$result.id                # completion ID
```

| Parameter | Type | Required | Constraints | Description |
|---|---|---|---|---|
| `Message` | `FoundryMessage` | Yes | — | Message object from `New-FoundryMessage`. |
| `Model` | `string` | Yes | — | Model ID (e.g. `phi-3-mini-128k-instruct-qnn-npu:3`). Check `Get-FoundryModelList`  |
| `Temperature` | `double` | No | 0.0 – 2.0 | Sampling temperature. |
| `MaxTokens` | `int` | No | 1 – 2048 | Maximum tokens to generate. |
| `TopP` | `double` | No | 0.0 – 1.0 | Nucleus sampling threshold. |
| `PresencePenalty` | `double` | No | -2.0 – 2.0 | Penalises tokens already present in the context. |
| `FrequencyPenalty` | `double` | No | -2.0 – 2.0 | Penalises tokens by their frequency in the context. |
| `User` | `string` | No | default: `pwshChat` | End-user identifier forwarded to the API. |
| `CountTokenOnly` | `switch` | No | — | Posts only `model` + `messages` to the token-count endpoint instead of generating a completion. **Not yet implemented in Foundry Local — currently returns HTTP 404.** |

The returned `PSCustomObject` has the following properties:

| Property | Source |
|---|---|
| `id` | `$response.id` |
| `object` | `$response.object` |
| `model` | `$response.model` |
| `message` | `$response.choices[0].message` |
| `successful` | `$response.successful` |

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
