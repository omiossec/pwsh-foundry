# Foundry Local Web Service REST API

Reference extracted from the Foundry Local C++ SDK web service source:
[`sdk_v2/cpp/src/service/`](https://github.com/microsoft/Foundry-Local/tree/main/sdk_v2/cpp/src/service)
(`web_service.cc` for route registration, individual handler `.cc` files for request/response fields).

## Service control

| Verb | URI | Request | Response |
|---|---|---|---|
| GET | `/status` | none | `{modelCachePath, endpoints, pid}` |
| POST | `/shutdown` | none | `{status: "shutting_down"}` |

## Model management

| Verb | URI | Request | Response |
|---|---|---|---|
| GET | `/models/loaded` | none | array of loaded model IDs |
| GET | `/models/load/{name}` | path `name` (required) | `status`: `"already_loaded"` \| `"loaded"` |
| GET | `/models/unload/{name}` | path `name` (required) | `status`: `"not_loaded"` \| `"unloaded"` |
| GET | `/v1/models` | none | `object: "list"`, `data[]` of `{id, object:"model", created, owned_by}` |
| GET | `/v1/models/{name}` | path `name` (required) | `{id, object, created, owned_by}` |

## OpenAI-compatible inference

### POST `/v1/chat/completions`

| Field | Location | Required | Type | Notes |
|---|---|---|---|---|
| `model` | body | Yes | string | |
| `messages` | body | Yes | array | |
| `stream` | body | No | boolean | default `false` |
| `tools` | body | No | array | |
| `stream_options` | body | No | object | |
| `stream_options.include_usage` | body | No | boolean | only read when `stream` is true |

**Response:** non-streaming returns an OpenAI-style chat completion JSON object; streaming returns SSE `ChatCompletionChunk` objects with `id`, `created`, `model`, `usage.prompt_tokens`, `usage.completion_tokens`, `usage.total_tokens`.

### POST `/v1/embeddings`

| Field | Location | Required | Type | Notes |
|---|---|---|---|---|
| `input` | body | Yes | string or string[] | |
| `model` | body | Yes | string | |

**Response:** `{model, data:[{index, embedding[]}], usage:{prompt_tokens:0, total_tokens:0}}` — token usage is not implemented and always reports `0`.

### POST `/v1/audio/transcriptions`

| Field | Location | Required | Type | Notes |
|---|---|---|---|---|
| `model` | body | Yes | string | |
| `filename` | body | Yes | string | |
| `stream` | body | No | boolean | default `false` |

**Response:** non-streaming returns JSON parsed from the audio session output (exact schema not defined in this file); streaming returns SSE text chunks terminated by `data: [DONE]`, with errors sent as `{"error":{"message":"..."}}`.

> Note: the handler's field checks (`model`, `filename`) are JSON-body checks in the source. OpenAI's real transcription API normally expects multipart file upload — confirm against actual client usage before relying on this.

## Responses API

### POST `/v1/responses`

| Field | Location | Required | Type | Notes |
|---|---|---|---|---|
| `model` | body | Yes | string | |
| `input` | body | Yes | string or array | array entries may have `type` (optional string) and `role` (optional string) |
| `stream` | body | No | boolean | |
| `max_output_tokens` | body | No | integer | |
| `previous_response_id` | body | No | string | |
| `store` | body | No | boolean | |

**Response:** `{id, created, model, output[], output_text, usage}`

### GET `/v1/responses`

| Field | Location | Required | Type | Default |
|---|---|---|---|---|
| `limit` | query | No | integer | `20` |
| `order` | query | No | string | `"desc"` |
| `after` | query | No | string | `""` |

**Response:** `{object:"list", data[], first_id, last_id, has_more}`

### GET `/v1/responses/{id}`

| Field | Location | Required |
|---|---|---|
| `id` | path | Yes |

**Response:** stored response object (as returned by the response store).

### DELETE `/v1/responses/{id}`

| Field | Location | Required |
|---|---|---|
| `id` | path | Yes |

**Response:** `{id, object:"response.deleted", deleted:true}`

### GET `/v1/responses/{id}/input_items`

| Field | Location | Required |
|---|---|---|
| `id` | path | Yes |

**Response:** `{object:"list", data[], first_id, last_id, has_more:false}`
