# Foundry Local 0.14 — module update plan

Working notes for adapting PwshFoundry to Foundry Local 0.14 (CLI 0.14.0 preview, SDK 2.4.1).
Sources: `sdk_v2/cpp/src/service/*` and `sdk_v2/cpp/src/contracts/*` on the `main` branch of
https://github.com/microsoft/foundry-local (not a 0.14 tag, so check against the installed build).

## 1. HTTP routes in 0.14 (`web_service.cc`)

Root = **Public Catalog API**. `/catalogs/local` = **Local Catalog (BYOM)**, which carries the same route set
with a separate response store. `/status` and `/shutdown` exist only at the root.

| Method | Path | Status vs module | Notes |
|---|---|---|---|
| GET | `/status` | already mapped | `{modelCachePath, endpoints[], pid, artifact_qualified_model_management}` |
| POST | `/shutdown` | **new** | `{"status":"shutting_down"}`; 403 on shared host; no admission wrapper |
| GET | `/models/loaded` | already mapped | `?details=true` returns `{model_id, model_path, context_length}` instead of id strings |
| GET | `/models/load/{name}` | already mapped | accepts alias; `?expected_model_path=`; returns `{model_id, model_path, context_length, status: loaded\|already_loaded}`; 409 path mismatch |
| GET | `/models/unload/{name}` | already mapped | returns `{status: unloaded\|not_loaded}` |
| GET | `/v1/models` | already mapped | one entry per variant, no aliases |
| GET | `/v1/models/{name}` | **new** | variant id only (no alias); 404 if unknown |
| POST | `/v1/chat/completions` | unchanged | penalties must be 0; model must be loaded |
| POST | `/v1/embeddings` | unchanged | `usage` now reported |
| POST | `/v1/audio/transcriptions` | unchanged | JSON body with `filename` (server-side path) |
| POST | `/v1/systemone` | **new** | decision models (`kev-4b`, `kev-0.8b`), task `typed-decision` |
| POST | `/v1/rank` | **new** | ranking models, task `text-ranking` |
| POST | `/v1/responses` | **new** | OpenAI Responses API |
| GET | `/v1/responses` | **new** | `?limit=` (1–100, default 20), `?order=` (default desc), `?after=` |
| GET | `/v1/responses/{id}` | **new** | 404 `response_not_found` |
| DELETE | `/v1/responses/{id}` | **new** | also deletes chained descendants |
| GET | `/v1/responses/{id}/input_items` | **new** | no paging; `has_more` always false |

Not present in 0.14: `/openai/download` and `/v1/chat/completions/tokenizer/encode/count`.

**Shared-host admission:** every route except `/shutdown` can return **503** with
"Shared host has no active sponsoring SDK manager or is stopping HTTP".

**Error envelope:**
`{"error":{"message","type":"invalid_request_error|server_error","param","code"}}`.
Status codes seen: 400, 403, 404, 409, 499 (client closed), 500, 503.

**Model id rules:**
- Chat, embeddings, audio, responses and `/v1/models/{name}` need the **variant id** (`xxx-generic-gpu:1`).
- Load, unload, rank and systemone accept an **alias**.
- Rank and systemone echo the resolved id.
- Systemone and rank do **not** need the model loaded, only cached. The runtime starts on demand; "Runtime busy" gives 503.

### `foundry server status` output in 0.14

```
State                    Ready
PID                      13376
Started                  2026-11-12 21:30:11Z
Uptime                   22m 40s
Web URLs                 http://127.0.0.1:61371
Public Catalog API       http://127.0.0.1:61371/v1/
Local Catalog (BYOM) API http://127.0.0.1:61371/catalogs/local/v1/
```

The current port regex still works: it takes the first `http://` line and the trailing digits.

## 2. Contracts

### `/v1/systemone` — `NonGenerativeRequest` (C++ member names, JSON keys not confirmed)

| Field | Type | Notes |
|---|---|---|
| `model` | string | C++ default `"kev"` |
| `state` | any JSON | context for the decision |
| `questions` | ordered name → `{type, criteria, instructions}` | allowed `type` values unknown |
| `temperature` | float | default 1.0 |

The handler returns `{model, answers, usage:{billing_units}}`. The shape of `answers` is still unknown.

### `/v1/rank` — `RankingRequest` (C++ member names, JSON keys not confirmed)

| Field | Type | Notes |
|---|---|---|
| `model` | string | C++ default `"clm"` |
| `context` | any JSON | |
| `question` | string | |
| `answers` | string[] | candidates |
| `temperature` | float | default 1.0 |

Response: the release notes mention `prob` per candidate (not verified).

### `/v1/responses` — `ResponseCreateParams`

- **Required:** `model`.
- **Input:** `input` is a string or an array of items:
  - `message` (`role` + `content`)
  - `function_call` (`call_id`, `name`, `arguments`)
  - `function_call_output` (`call_id`, `output`)
  - `custom_tool_call`
  - `custom_tool_call_output`
  - `reasoning`
- **Content parts:**
  - `input_text` / `output_text` / `text`
  - `input_image` (`image_url`, or the Foundry-specific `image_data`; `detail`, `media_type`)
  - `input_file`
  - `input_audio` (`data`, `format`)
- **Optional fields:** `instructions`, `previous_response_id`, `store` (default **false**), `temperature`, `top_p`,
  `max_output_tokens`, `seed`, `stream`, `metadata` (string values only), `user`,
  `reasoning.effort` / `reasoning.generate_summary`, `parallel_tool_calls`, `allowed_tools`, `extra`.
- **`text.format`:** `{type, schema}` or `{type, grammar}` (Lark).
- **`tools`:** only `function` (flat Responses shape; the nested Chat shape is accepted as a fallback) and `custom`.
  Built-in tool types are rejected with 400.
- **`tool_choice`:** `auto|none|required`, `{type:function,name}`, `{type:custom,name}`, or
  `{type:allowed_tools, mode: auto|required, tools:[{type,name}]}`.
- **Unknown keys are silently ignored**, so cmdlets must validate their own input.
- `presence_penalty` / `frequency_penalty`: only 0 is supported.

**Response object:**
- `id`, `object:"response"`, `created_at`, `status` (`in_progress|completed|failed|cancelled|incomplete`), `model`
- `output_text` (always present)
- `output[]` items:
  - `message`: `content` is made of `output_text`, `refusal` and `output_audio` parts
  - `function_call`: `call_id`, `name`, `arguments`
  - `custom_tool_call`
  - `reasoning`: `summary[]`
- `usage{input_tokens, output_tokens, total_tokens, input_tokens_details.cached_tokens, output_tokens_details.reasoning_tokens}`
- `error{code,message}`, `incomplete_details{reason}`, `previous_response_id`, `store`, `tools`, `tool_choice`, `metadata`

**Streaming (SSE, `event:` + `data:` frames, ends with `data: [DONE]`):**
- Lifecycle: `response.created`, `response.in_progress`, then a terminal `response.completed`, `.incomplete` or `.failed`.
- Output items: `response.output_item.added` / `.done` and `response.content_part.added` / `.done`.
- Text and reasoning: `response.output_text.delta` / `.done` and `response.reasoning.delta` / `.done`.
- Tool calls: `response.function_call_arguments.delta` / `.done` and `response.custom_tool_call_input.delta` / `.done`.

## 3. Changes to existing module code

| File | Change |
|---|---|
| `Private/Invoke-FoundryApiRequest.ps1` | Add the new actions (`model-get`, `decision`, `rank`, `response-create`, `response-list`, `response-get`, `response-delete`, `response-input-items`, `shutdown`). Add `DELETE` to `-Method`. Add a `-Query [hashtable]` parameter. Add `-Catalog Public\|Local` (default Public, Local adds the `/catalogs/local` prefix). Set a minimum version per action (0.14 for the new ones). Fix `ValidateSet`, which is missing `model-download` even though `$pathMap` has it. Parse the error envelope (`error.message` / `error.code`) and add clear messages for 503, 409 and 499. |
| `Private/Get-FoundryServicePort.ps1` | Detect a stopped server from the `State` row (anything other than `Ready`) instead of matching `Not running`. Check what `foundry server status` prints when the server is stopped. Fix indentation (lines 8–21). |
| `Public/Get-FoundryStatus.ps1` | Help text still says `/openai/status`. Return a typed object from the new fields. |
| `Public/Get-FoundryModelCache.ps1` | Actually lists *loaded* models. Rename it, or add `-Detailed` (`?details=true`). Remove the debug `Write-Verbose $response.getType()`. Get the cache path from `/status`. |
| `Private/Initialize-FoundryModel.ps1` | Use the `model_id` returned by `/models/load` instead of calling `models-loaded` again before and after. |
| `Public/New-FoundryAudioTranscription.ps1` | Replace the duplicated load logic (lines 115–146) with `Initialize-FoundryModel`. |
| `Public/Deploy-FoundryModel.ps1` | Return the load response (`model_id`, `status`). |
| `Public/Save-FoundryModel.ps1` | Use the unload response `status` (`unloaded` / `not_loaded`). |
| `Public/Stop-FoundryWebServer.ps1` | Try `POST /shutdown` first, fall back to `Kill()`, and handle the 403 on a shared host. |
| `Public/New-FoundryChat.ps1` (l.159, 163) | Non-zero `presence_penalty` / `frequency_penalty` returns 400 on 0.14: warn, throw, or stop sending them. |
| `Public/Get-FoundryModelList.ps1` | Add a `task` property (`typed-decision`, `text-ranking`, …) if the 0.14 CLI JSON includes it. |
| `Public/New-FoundryEmbedding.ps1` | Check the shape of `usage` (now token counts). |
| `Public/Start-FoundryWebServer.ps1:153`, `Private/Get-FoundryModelListFromSdk.ps1:97` | SDK pinned to `Microsoft.AI.Foundry.Local.WinML 1.2.0`. Check whether to move to 2.4.x. |
| `Classes/FoundryTool.ps1` | Add a method that emits the flat Responses tool shape (the nested Chat shape is accepted as a fallback). |

## 4. New cmdlets

| Cmdlet | Route | Notes |
|---|---|---|
| `Invoke-FoundryDecision` | `POST /v1/systemone` | `-Model kev-4b -State <object> -Question <[ordered]> [-Temperature]`. Needs cached only, not loaded; check task `typed-decision`. |
| `Invoke-FoundryRank` | `POST /v1/rank` | `-Model -Question -Answer <string[]> [-Context] [-Temperature]`. Returns candidates sorted by score. |
| `New-FoundryResponse` | `POST /v1/responses` | `-Model -Input -Instructions -PreviousResponseId -Store -Tool -ToolChoice -JsonSchema -Grammar -MaxOutputTokens -Temperature -TopP -Seed -ReasoningEffort -Metadata`. Returns `output_text` by default and the full object with `-Raw`. Bind `-PreviousResponseId` from pipeline `id`. |
| `Get-FoundryResponse` | `GET /v1/responses[/{id}]` | `-Id`, or `-Limit -Order -After`. Only works for responses created with `store=true`. |
| `Get-FoundryResponseInputItem` | `GET /v1/responses/{id}/input_items` | |
| `Remove-FoundryResponse` | `DELETE /v1/responses/{id}` | `SupportsShouldProcess`. Also deletes chained descendants. |
| `Get-FoundryModel` | `GET /v1/models/{name}` | Or add `-Name` to an existing cmdlet. |

## 5. Findings on the installed 0.14.0 (2026-11-13)

- `foundry --version` prints `0.14.0`.
- `foundry decide <model>` question types:
  - `--noul id=instructions`: predicate; returns the probability it is true.
  - `--choice id={"key":"label",...}`: choice.
  - `--score id=["low","high"]`: ordered score.
  - Also: `--state <json>`; `--temperature` must be exactly 1.0 for decision models; `-f/--stdin` take a full
    request JSON.
- `foundry rank <model>` options: `--answer` (repeatable), `--question` (optional), `--context <json>`,
  `--temperature` (in (0, 100]).
- `foundry model list --output json` has **no `task` field**: kev and clm show `"type":"Unknown"`.
  `--type decision|ranking` returns nothing.
- `foundry model info kev-0.8b -o json` exposes `capabilities: "noul,choice,score,structured-input"` and
  `contextLength`. Use `capabilities` to detect decision models.
- **Foundry bug:** `POST /v1/systemone` with kev-0.8b returns
  `400 Invalid request: model 'kev-0.8b' has task 'decision'; expected 'typed-decision'`, and
  `foundry decide kev-0.8b` says "'kev-0.8b' is not a decision model". Decisions cannot be tested end to end
  on this build.
- This request body passed parsing (the error came later, at model resolution), so the JSON keys look right:
  `{"model","state":{...},"questions":{"<id>":{"type":"noul","instructions":"..."},`
  `"<id>":{"type":"choice","criteria":{...}},"<id>":{"type":"score","criteria":[...]}},"temperature":1.0}`

## 6. Open questions

- Exact JSON keys and response shapes for `/v1/systemone` and `/v1/rank`. Get them from the `.cc` that implements
  `from_json` (`contracts/non_generative*.cc`), or from `foundry decide --help` / `foundry rank --help` plus a real call.
- Allowed values of `questions.<name>.type` for kev models.
- Do kev models work at the root, or only under `/catalogs/local`? The package guide mentions local-catalog ids.
  The server status output suggests the root (public catalog).
- What does `foundry server status` print when the server is stopped?
- Streaming (SSE): keep it unsupported for now, or add a reader?
- New 0.14 CLI commands (`foundry decide`, `rank`, `embed`, `index`): could serve as a fallback when the service is down.

## TODO

- [x] Confirm `/v1/systemone` request keys (body parses; see section 5)
- [ ] Get the `/v1/systemone` response shape (blocked by the `decision` vs `typed-decision` Foundry bug)
- [x] Download `clm-v0.1-8b` (capabilities: `candidate-ranking,structured-input,action-cache`)
- [x] Confirm `/v1/rank` request keys (`model`, `question`, `answers`, `context` parse)
- [ ] Get the `/v1/rank` response shape (blocked: same bug, catalog task `ranking` vs expected `text-ranking`)
- [ ] Report the `decision` vs `typed-decision` task mismatch upstream (microsoft/foundry-local; draft written)
- [ ] Check `foundry server status` output when the server is stopped
- [x] Check whether kev models work at the root route (yes: the root route reaches the model check)
- [x] Check whether `foundry model list --output json` exposes `task` (no; use `model info` `capabilities`)
- [x] `Invoke-FoundryApiRequest`: new actions, `DELETE`, `-Query`, `-Catalog`, per-action minimum version, error envelope
- [x] `Invoke-FoundryApiRequest`: add `model-download` to `ValidateSet`
- [x] Rewrite `tests/Invoke-FoundryApiRequest.Tests.ps1` for the `-Action` API (38 tests passing)
- [ ] `Get-FoundryServicePort`: detect a stopped server from the `State` row and fix indentation
- [ ] `Get-FoundryStatus`: fix help text and return a typed object
- [ ] `Get-FoundryModelCache`: rename or add `-Detailed`; remove the debug verbose line
- [ ] `Initialize-FoundryModel`: use the `model_id` from the load response
- [ ] `New-FoundryAudioTranscription`: reuse `Initialize-FoundryModel`
- [ ] `Deploy-FoundryModel` / `Save-FoundryModel`: use the load/unload response `status`
- [ ] `Stop-FoundryWebServer`: try `POST /shutdown` first
- [ ] `New-FoundryChat`: handle the 0.14 penalty restriction
- [ ] `Get-FoundryModelList`: add `task`
- [ ] `New-FoundryEmbedding`: check `usage`
- [ ] Decide whether to bump the SDK pin from 1.2.0 to 2.4.x
- [ ] `FoundryTool`: add a flat Responses-shape serializer
- [x] New `Invoke-FoundryDecision` (19 unit tests; live call reaches the service and surfaces the task bug)
- [ ] `Invoke-FoundryDecision`: project `answers` into per-question objects once the response shape is known
- [x] New `Invoke-FoundryRank` (16 unit tests; live call reaches the service and surfaces the task bug)
- [ ] `Invoke-FoundryRank`: project the result into per-candidate objects sorted by score once the response shape is known
- [ ] New `New-FoundryResponse`
- [ ] New `Get-FoundryResponse`, `Get-FoundryResponseInputItem`, `Remove-FoundryResponse`
- [ ] New `Get-FoundryModel` (`/v1/models/{name}`)
- [ ] Pester unit tests for every new or changed function (mock `Invoke-FoundryApiRequest`)
- [ ] Integration tests for kev / rank / responses (`-Tag Integration`)
- [ ] Update `FunctionsToExport` and bump `ModuleVersion` (currently 0.2.1)
- [ ] Update README
- [ ] Run PSScriptAnalyzer and fix the warnings
