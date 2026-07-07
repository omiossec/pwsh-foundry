# pwsh-foundry

**PwshFoundry** is a PowerShell module (v0.1.10, alpha) that wraps the [Microsoft Foundry Local](https://github.com/microsoft/foundry-local) CLI and REST API so that PowerShell users and automation scripts can interact with local AI workloads without dropping into raw `afoundry` commands or hand-crafting HTTP requests.

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
> See [API endpoint changes (v0.10.0)](#api-endpoint-changes-v0100) for the full mapping.

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

### `Get-FoundryVersion`

Returns the installed Foundry CLI version, or indicates SDK-only mode when the CLI is absent.
The result is cached for 60 minutes; use `-ByPassCache` to force a fresh lookup.

```powershell
Get-FoundryVersion

# Force a fresh lookup
Get-FoundryVersion -ByPassCache
```

| Parameter | Type | Required | Description |
|---|---|---|---|
| `ByPassCache` | `switch` | No | Skips the 60-minute in-memory cache and queries the CLI directly. |

The returned `PSCustomObject` has the following properties:

| Property | Description |
|---|---|
| `Source` | `'CLI'` when the Foundry CLI was found; `'SDK'` when only the .NET SDK is available. |
| `Version` | Semver string (e.g. `'0.10.0'`) parsed from CLI output, or `$null` in SDK mode. |
| `Message` | Raw CLI version string, or a descriptive SDK-mode message. |

The `Source` and `Version` properties drive the automatic API-path selection in `Invoke-FoundryApiRequest` (see [API endpoint changes (v0.10.0)](#api-endpoint-changes-v0100)).

---

### `Get-FoundryModelList`

Lists all models in the Foundry catalogue (downloaded or not).
Results are cached for 60 minutes; use `-ByPassCache` to force a fresh query.

When the Foundry CLI is installed, it calls `foundry model list --output json`.
When only the SDK is available (`Get-FoundryVersion` returns `Source = 'SDK'`), it compiles and runs a temporary .NET host that queries the catalogue via `Microsoft.AI.Foundry.Local`. The .NET 8 SDK is required in this case.

```powershell
Get-FoundryModelList

# Force a fresh catalogue query
Get-FoundryModelList -ByPassCache
```

| Parameter | Type | Required | Description |
|---|---|---|---|
| `ByPassCache` | `switch` | No | Skips the 60-minute in-memory cache and queries the source directly. |

Returns objects with the following properties:

| Property | Description |
|---|---|
| `alias` | Short model alias (e.g. `qwen2.5-0.5b`). |
| `id` | Full versioned model ID (e.g. `qwen2.5-0.5b-instruct-generic-cpu:4`). |
| `displayName` | Human-readable model name. |
| `type` | Model task: `Chat`, `Embedding`, `Multimodal`, or `Speech`. |
| `device` | Target hardware: `Cpu`, `Gpu`, or `Npu`. |
| `fileSizeMb` | Download size in megabytes. |
| `cached` | `$true` if the model is already downloaded locally. |
| `license` | License identifier (e.g. `MIT`). |
| `supportsToolCalling` | `$true` if the model supports tool/function calling. |

> **Note** — in SDK mode only CPU-compatible models are returned, because the SDK enumerates variants for the registered execution providers only. CLI mode returns all variants including NPU/GPU.

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

### `New-FoundryChatContext`

Creates a `FoundryChatContext` object for multi-turn conversations. It is seeded with a system prompt and an initial user prompt, then grows as the conversation continues — pass it to `New-FoundryChat -Context` instead of `-Message` to have each call automatically append the assistant's reply to the history.

```powershell
$ctx    = New-FoundryChatContext -UserPrompt 'Explain quantum computing in plain English'
$result = New-FoundryChat -Context $ctx -Model 'qwen2.5-0.5b-instruct-generic-cpu'
$result.message.content

# Continue the conversation — $ctx now includes the assistant's prior reply
$ctx.AddUserPrompt('Now explain it to a 5 year old')
$result2 = New-FoundryChat -Context $ctx -Model 'qwen2.5-0.5b-instruct-generic-cpu'
$result2.message.content
```

| Parameter | Type | Required | Description |
|---|---|---|---|
| `UserPrompt` | `string` | Yes | The initial user turn content. |
| `SystemPrompt` | `string` | No | Overrides the default system prompt (`You are a helpful assistant`). |

The object exposes the following methods:

| Method | Description |
|---|---|
| `AddUserPrompt([string])` | Appends a new user turn to the conversation. |
| `AddAssistantResponse([string])` | Appends an assistant turn to the conversation. Called automatically by `New-FoundryChat` after a successful `-Context` call. |
| `GetMessages()` | Returns the full accumulated message history as an array of `{role; content}` hashtables. |

---

### `Get-FoundryStatus`

Returns the status of the local Foundry OpenAI-compatible endpoint.

```powershell
Get-FoundryStatus
```

---

### `Start-FoundryWebServer`

Compiles and launches a minimal .NET host that uses the `Microsoft.AI.Foundry.Local` SDK to download execution providers, load a model, and expose an OpenAI-compatible HTTP endpoint as a background process.
Call `Stop-FoundryWebServer` to shut it down.

```powershell
$srv = Start-FoundryWebServer -ModelAlias 'qwen2.5-0.5b'
$srv.Endpoint   # e.g. "http://127.0.0.1:52495/v1"
$srv.ModelId
$srv.ProcessId
```

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `ModelAlias` | `string` | Yes | — | Model alias or ID from the Foundry catalogue (e.g. `qwen2.5-0.5b`). |
| `Port` | `int` | No | `52495` | TCP port the web service will listen on. |
| `AppName` | `string` | No | `pwsh_foundry` | Application name forwarded to the SDK for telemetry. |
| `LogLevel` | `string` | No | `Warning` | SDK log verbosity: `Trace`, `Debug`, `Information`, `Warning`, `Error`, `Critical`, `None`. |
| `TimeoutSeconds` | `int` | No | `300` | Maximum seconds to wait for the server readiness signal. |

Returns a `PSCustomObject` with `Endpoint`, `ModelId`, `Port`, and `ProcessId`.

> **Requires the .NET 8 SDK** (`dotnet` on `PATH`). The cmdlet compiles a temporary C# host project using `Microsoft.AI.Foundry.Local.WinML` 1.2.0.

---

### `Stop-FoundryWebServer`

Terminates the background Foundry web server started by `Start-FoundryWebServer`, removes its temporary build directory, and clears module-level server state.

```powershell
Stop-FoundryWebServer
```

---

### `Save-FoundryModel`

Downloads a model to the local Foundry service by posting a download request with the model URI, provider type, and model ID.
The model ID must exist in the Foundry catalogue (`Get-FoundryModelList`) — a terminating error is thrown otherwise.

> **Not available in Foundry Local v0.10.0+** — the `/openai/download` endpoint was removed in the new API.
> A terminating error is thrown when this cmdlet is called against a v0.10.0+ service.

```powershell
Save-FoundryModel -ModelID 'Phi-4-mini-instruct-generic-cpu:4' `
                  -ModelURI 'azureml://registries/azureml/models/Phi-4-mini-instruct-generic-cpu/versions/4'
```

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `ModelURI` | `string` | Yes | — | Full URI of the model in the registry. |
| `ProviderType` | `string` | No | `AzureFoundryLocal` | Provider type passed to the download API. |
| `ModelID` | `string` | Yes | — | Model ID as it appears in `Get-FoundryModelList` (e.g. `Phi-4-mini-instruct-generic-cpu:4`). |

---

### `New-FoundryChat`

Sends a chat completion request to the local Foundry service and returns a mapped result object.

Since Foundry Local **0.10.0**, the service no longer auto-loads a model on the first request.
`New-FoundryChat` handles this automatically: it checks whether the requested model is loaded and calls the load endpoint if not. The first call for an unloaded model may take additional time while the model initialises.

Pass the bare model ID (without the `:version` suffix) — both forms are accepted.

Accepts either a single-turn `-Message` (from `New-FoundryMessage`) or a multi-turn `-Context` (from `New-FoundryChatContext`) — the two are mutually exclusive parameter sets.

```powershell
$msg    = New-FoundryMessage -UserPrompt 'Write a haiku about PowerShell'
$result = New-FoundryChat -Message $msg -Model 'qwen2.5-0.5b-instruct-generic-cpu'

$result.message.content   # assistant reply text
$result.model             # model that handled the request
$result.id                # completion ID
```

Multi-turn, using a `FoundryChatContext` (see [`New-FoundryChatContext`](#new-foundrychatcontext)):

```powershell
$ctx    = New-FoundryChatContext -UserPrompt 'Write a haiku about PowerShell'
$result = New-FoundryChat -Context $ctx -Model 'qwen2.5-0.5b-instruct-generic-cpu'

$ctx.AddUserPrompt('Now write one about Bash')
$result2 = New-FoundryChat -Context $ctx -Model 'qwen2.5-0.5b-instruct-generic-cpu'
```

| Parameter | Type | Required | Constraints | Description |
|---|---|---|---|---|
| `Message` | `FoundryMessage` | Yes (ParameterSet `Message`) | — | Message object from `New-FoundryMessage`. Mutually exclusive with `Context`. |
| `Context` | `FoundryChatContext` | Yes (ParameterSet `Context`) | — | Conversation object from `New-FoundryChatContext`. The assistant's reply is appended to it via `AddAssistantResponse` after a successful call, so the same object can be reused for the next turn. Mutually exclusive with `Message`. |
| `Model` | `string` | Yes | — | Model ID from `Get-FoundryModelList` (e.g. `qwen2.5-0.5b-instruct-generic-cpu`). The `:version` suffix is optional. |
| `Temperature` | `double` | No | 0.0 – 2.0 | Sampling temperature. |
| `MaxTokens` | `int` | No | 1 – 2048 | Maximum tokens to generate. |
| `TopP` | `double` | No | 0.0 – 1.0 | Nucleus sampling threshold. |
| `PresencePenalty` | `double` | No | -2.0 – 2.0 | Penalises tokens already present in the context. |
| `FrequencyPenalty` | `double` | No | -2.0 – 2.0 | Penalises tokens by their frequency in the context. |
| `User` | `string` | No | default: `pwshChat` | End-user identifier forwarded to the API. |
| `CountTokenOnly` | `switch` | No | — | Posts to the token-count endpoint instead of generating a completion. **Removed in Foundry Local v0.10.0+** — throws a terminating error on newer services. Was `/v1/chat/completions/tokenizer/encode/count` on older versions. |
| `LogFilePath` | `string` | No | default: temp folder | Path to a log file. When the request completes, the system prompt, user prompt, and assistant response are appended to it as a JSON-line entry via `New-FoundryLogEntries`. If omitted, entries are logged to `PwshFoundry_ChatLog.jsonl` in the current user's temp directory. An invalid path (or one whose parent directory doesn't exist) throws a terminating error before any request is sent. Not applied when `-CountTokenOnly` is used. |

The returned `PSCustomObject` has the following properties:

| Property | Source |
|---|---|
| `id` | `$response.id` |
| `object` | `$response.object` |
| `model` | `$response.model` |
| `message` | `$response.choices[0].message` |
| `successful` | `$response.successful` |

---

### `New-FoundryAudioTranscription`

Transcribes an audio file to text using a local Foundry Whisper model, via the `/v1/audio/transcriptions` endpoint.

> **Requires Foundry Local v1.1.0**, installed manually — see the CLI version notice at the top of this document.

```powershell
New-FoundryAudioTranscription -ModelId 'whisper-1' -AudioFile 'C:\recordings\meeting.mp3'

# With language and response format
New-FoundryAudioTranscription -ModelId 'whisper-large-v3' -AudioFile './interview.wav' `
                              -Language 'fr' -ResponseFormat 'json'
```

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `ModelId` | `string` | Yes | — | Whisper model ID (must match `whisper`, case-insensitive). |
| `AudioFile` | `string` | Yes | — | Path to the audio file. Must exist and have a `.mp3`, `.wav`, `.flac`, `.ogg`, or `.webm` extension. |
| `Language` | `string` | No | `en` | Source language hint passed to the model. |
| `Temperature` | `double` | No | — | Sampling temperature, `0.0`–`1.0`. |
| `ResponseFormat` | `string` | No | `text` | One of `text`, `json`, `verbose_json`. |
| `LogFilePath` | `string` | No | default: temp folder | Path to a log file. When the request completes, an entry is appended via `New-FoundryLogEntries` recording the model, the audio file/language as the "user prompt", and the transcription result as the "assistant response". If omitted, entries are logged to `PwshFoundry_ChatLog.jsonl` in the current user's temp directory. An invalid path throws a terminating error before any request is sent. |

---

## API endpoint changes (v0.10.0)

Foundry Local CLI **0.10.0** (SDK **1.10**) reorganised the REST API.
The module detects the active version via `Get-FoundryVersion` and automatically routes each request to the correct path — no manual changes are required.

| Action | Old path (`< 0.10.0`) | New path (`≥ 0.10.0`) |
|---|---|---|
| Service status | `GET /openai/status` | `GET /status` |
| Full model catalogue | `GET /foundry/list` | `GET /v1/models` |
| Loaded models | `GET /openai/models` | `GET /models/loaded` |
| Load a model | `POST /openai/load/{name}` | `GET /models/load/{name}` |
| Unload a model | `POST /openai/unload/{name}` | `GET /models/unload/{name}` |
| Download a model | `POST /openai/download` | *(removed — throws error)* |
| Token count | `POST /v1/chat/completions/tokenizer/encode/count` | *(removed — throws error)* |
| Chat completion | `POST /v1/chat/completions` | `POST /v1/chat/completions` *(unchanged)* |
| Audio transcription | `POST /v1/audio/transcriptions` | `POST /v1/audio/transcriptions` *(unchanged)* |

SDK mode (CLI absent) is treated as `≥ 0.10.0` and uses the new paths.

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
