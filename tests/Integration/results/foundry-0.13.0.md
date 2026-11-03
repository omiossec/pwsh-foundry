# PwshFoundry compatibility - Foundry CLI 0.13.0

| | |
|---|---|
| Foundry CLI | 0.13.0 |
| Baseline | none |
| Module | 0.2.1 |
| PowerShell | 7.6.3 |
| OS | Microsoft Windows 10.0.26300 |
| Date | 2026-11-03T19:53:31.0427902+01:00 |
| Models | chat: qwen2.5-0.5b-instruct-generic-cpu, embedding: qwen3-embedding-0.6b-generic-gpu, audio: openai-whisper-tiny-generic-cpu |

**Pass:** 16 - **Diff:** 0 - **Fail:** 10 (regressions: 0) - **Skip:** 2

| Feature | Command | Status | Duration (ms) | Details |
|---|---|---|---|---|
| CliVersion | Get-FoundryVersion | Pass | 49 | Message: 0.13.0 |
| ServicePort | Get-FoundryServicePort (private, foundry server status) | Pass | 62 | Port: 60288 |
| CliModelListJson | foundry model list --output json (private Invoke-FoundryCli) | Pass | 75 | ModelCount: 48<br>Types: Chat, Embedding, Multimodal, Speech<br>Devices: Cpu, Gpu, Npu |
| ModelList | Get-FoundryModelList | Pass | 60 | Count: 48<br>Cached: 23 |
| ModelResolve | Resolve-FoundryModel (private, alias/id/versioned id) | Pass | 20 |  |
| Status | Get-FoundryStatus | Pass | 2144 | Status: {"artifact_qualified_model_management":true,"endpoints":["http://127.0.0.1:60288"],"modelCachePath":"C:\\Users\\olivi/.foundry/cache/models","pid":83448} |
| ApiModelList | Invoke-FoundryApiRequest -Action model-list (private) | Pass | 2089 |  |
| ModelUnload | Invoke-FoundryApiRequest -Action model-unload (private) | Pass | 6345 |  |
| ModelCacheEmpty | Get-FoundryModelCache (no model loaded) | Skip | 0 | Other models are still loaded in the service |
| ChatAutoLoad | New-FoundryChat (model not loaded) | Fail | 4227 | [FoundryApiRequestError,Invoke-FoundryApiRequest] Foundry API request failed (GET http://localhost:60288/models/load/qwen2.5-0.5b-instruct-generic-cpu): Response status code does not indicate success: 404 (Not Found). Server response: { "error": { "code": null, "message": "Model not found: No model matching \u0027qwen2.5-0.5b-instruct-generic-cpu\u0027", "param": null, "type": "invalid_request_error" } } |
| DeployModel | Deploy-FoundryModel | Pass | 6628 |  |
| ModelCache | Get-FoundryModelCache (model loaded) | Pass | 2091 | Loaded: qwen2.5-0.5b-instruct-generic-cpu:4, openai-whisper-tiny-generic-cpu:4 |
| SaveModelCached | Save-FoundryModel (already cached) | Pass | 111 | Message: Model 'qwen2.5-0.5b-instruct-generic-cpu:4' is already cached. Use --force to download it again. |
| SaveModelUnknown | Save-FoundryModel (unknown model) | Pass | 3 |  |
| ChatMessage | New-FoundryMessage + New-FoundryChat | Fail | 4182 | [FoundryApiRequestError,Invoke-FoundryApiRequest] Foundry API request failed (POST http://localhost:60288/v1/chat/completions): Response status code does not indicate success: 404 (Not Found). Server response: { "error": { "code": null, "message": "Model not found: No model matching \u0027qwen2.5-0.5b-instruct-generic-cpu\u0027", "param": null, "type": "invalid_request_error" } } |
| ChatMaxTokens | New-FoundryChat -MaxTokens | Fail | 4172 | [FoundryApiRequestError,Invoke-FoundryApiRequest] Foundry API request failed (POST http://localhost:60288/v1/chat/completions): Response status code does not indicate success: 404 (Not Found). Server response: { "error": { "code": null, "message": "Model not found: No model matching \u0027qwen2.5-0.5b-instruct-generic-cpu\u0027", "param": null, "type": "invalid_request_error" } } |
| ChatCountToken | New-FoundryChat -CountTokenOnly | Fail | 4177 | [FoundryApiRequestError,Invoke-FoundryApiRequest] Foundry API request failed (POST http://localhost:60288/v1/chat/completions): Response status code does not indicate success: 404 (Not Found). Server response: { "error": { "code": null, "message": "Model not found: No model matching \u0027qwen2.5-0.5b-instruct-generic-cpu\u0027", "param": null, "type": "invalid_request_error" } } |
| ChatContext | New-FoundryChatContext + New-FoundryChat -Context | Fail | 4182 | [FoundryApiRequestError,Invoke-FoundryApiRequest] Foundry API request failed (POST http://localhost:60288/v1/chat/completions): Response status code does not indicate success: 404 (Not Found). Server response: { "error": { "code": null, "message": "Model not found: No model matching \u0027qwen2.5-0.5b-instruct-generic-cpu\u0027", "param": null, "type": "invalid_request_error" } } |
| ChatTools | New-FoundryTool + New-FoundryChat -Tools -ToolChoice | Fail | 4219 | [FoundryApiRequestError,Invoke-FoundryApiRequest] Foundry API request failed (POST http://localhost:60288/v1/chat/completions): Response status code does not indicate success: 404 (Not Found). Server response: { "error": { "code": null, "message": "Model not found: No model matching \u0027qwen2.5-0.5b-instruct-generic-cpu\u0027", "param": null, "type": "invalid_request_error" } } |
| ChatErrors | New-FoundryChat (unknown model, bad ToolChoice, bad log path) | Pass | 2122 |  |
| ChatLogFile | New-FoundryChat -LogFilePath | Fail | 3 | Assertion failed: the chat log file 'C:\Users\olivi\AppData\Local\Temp\PwshFoundryCompat_20261103195222\chat-log.jsonl' was written |
| EmbeddingSingle | New-FoundryEmbedding -Text | Fail | 4163 | [FoundryApiRequestError,Invoke-FoundryApiRequest] Foundry API request failed (GET http://localhost:60288/models/load/qwen3-embedding-0.6b-generic-gpu): Response status code does not indicate success: 404 (Not Found). Server response: { "error": { "code": null, "message": "Model not found: No model matching \u0027qwen3-embedding-0.6b-generic-gpu\u0027", "param": null, "type": "invalid_request_error" } } |
| EmbeddingBatch | New-FoundryEmbedding (pipeline batch) | Fail | 4161 | [FoundryApiRequestError,Invoke-FoundryApiRequest] Foundry API request failed (GET http://localhost:60288/models/load/qwen3-embedding-0.6b-generic-gpu): Response status code does not indicate success: 404 (Not Found). Server response: { "error": { "code": null, "message": "Model not found: No model matching \u0027qwen3-embedding-0.6b-generic-gpu\u0027", "param": null, "type": "invalid_request_error" } } |
| CompareEmbedding | Compare-FoundryEmbedding | Fail | 3 | Assertion failed: EmbeddingBatch produced vectors |
| AudioText | New-FoundryAudioTranscription | Pass | 4536 | Text: And lots of times you need to give people more than one link at a time. You a band could give their fans a couple new vi... |
| AudioJson | New-FoundryAudioTranscription -ResponseFormat json -Language | Pass | 4554 | Model: openai-whisper-tiny-generic-cpu:4 |
| AudioErrors | New-FoundryAudioTranscription (missing file, unknown model) | Pass | 6 |  |
| WebServer | Start-FoundryWebServer + Stop-FoundryWebServer (SDK) | Skip | 0 | Opt-in: use -IncludeWebServer |

