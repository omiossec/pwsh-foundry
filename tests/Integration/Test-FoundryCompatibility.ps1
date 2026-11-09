#Requires -Version 7.4

<#
.SYNOPSIS
    Runs every PwshFoundry feature against the locally installed Foundry CLI and reports
    what passes, what fails and what behaves differently from a previous CLI version.
.DESCRIPTION
    Foundry Local changes often, and each new CLI version can move REST routes, change JSON
    shapes or break model-name handling. This script exercises every public function of the
    module (plus the private helpers that talk to the CLI and the REST API) against the real
    Foundry service and models on this machine.

    It needs a real Foundry install and real hardware (CPU/GPU/NPU models), so it cannot run
    on a GitHub runner. Run it locally after each Foundry CLI upgrade.

    For each feature the script records:
      - a status: Pass, Fail, Diff or Skip
      - an observation: stable facts about the result (property names, types, error ids,
        dimensions, flags). Free text such as model answers is never compared.
      - informational details (durations, sample output) that are reported but not compared.

    Results are saved to tests/Integration/results/foundry-<version>.json and a Markdown report
    next to it. The observations are compared with the results of another CLI version
    (by default the closest lower version found in the results folder):
      - Pass : the feature works and behaves like the baseline (or there is no baseline)
      - Diff : the feature works but its observation differs from the baseline
      - Fail : the feature threw, wrote an error or failed an assertion. When it passed on
               the baseline version it is flagged as a regression.
      - Skip : a prerequisite is missing (model not in the catalog, opt-in test not requested)
.PARAMETER ChatModel
    Chat model id used for chat, tool calling and model management tests. Must support tool
    calling. Defaults to the first cached model of: qwen3-0.6b, phi-4-mini, then any
    cached chat model that supports tool calling.
.PARAMETER EmbeddingModel
    Embedding model id. Defaults to qwen3-embedding-0.6b, then any cached embedding model.
.PARAMETER AudioModel
    Whisper model alias or id. Defaults to whisper-tiny, then any cached speech model.
.PARAMETER AudioFile
    Audio file to transcribe. Defaults to samples/Recording.mp3.
.PARAMETER Feature
    Names (wildcards allowed) of the features to run. Defaults to all of them.
    Use -ListFeature to print the names.
.PARAMETER ListFeature
    Lists the available features and exits.
.PARAMETER IncludeWebServer
    Also tests Start-FoundryWebServer / Stop-FoundryWebServer. Off by default: it compiles a
    .NET host, restores NuGet packages and loads a model through the SDK, which is slow.
.PARAMETER WebServerPort
    Port used by the web server test. Defaults to 52495.
.PARAMETER BaselinePath
    Result file (foundry-<version>.json) to compare with. Defaults to the closest lower
    version found in ResultsPath, or the highest other version when there is no lower one.
.PARAMETER ResultsPath
    Folder where results and reports are written. Defaults to tests/Integration/results.
.PARAMETER NoSave
    Runs the tests and prints the report without writing any file.
.PARAMETER PassThru
    Also emits one result object per feature to the pipeline.
.PARAMETER Force
    Runs even when a CI environment is detected.
.EXAMPLE
    ./tests/Integration/Test-FoundryCompatibility.ps1

    Runs every feature with automatically selected models and compares with the previous
    CLI version found in tests/Integration/results.
.EXAMPLE
    ./tests/Integration/Test-FoundryCompatibility.ps1 -Feature Chat* -ChatModel 'Phi-4-mini-instruct-generic-gpu'
.EXAMPLE
    ./tests/Integration/Test-FoundryCompatibility.ps1 -IncludeWebServer -BaselinePath ./tests/Integration/results/foundry-0.11.0.json
.OUTPUTS
    With -PassThru, one PSCustomObject per feature with Feature, Command, Status, Regression,
    Differences, Error, DurationMs, Observation and Info. The script exits with code 1 when a
    feature fails.
.NOTES
    The ModelUnload / ChatAutoLoad features unload the chat model from the running service
    to check that the module loads it again on demand.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Interactive colored console report; results are also saved and emitted with -PassThru.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
    Justification = 'IncludeWebServer and WebServerPort are used inside feature scriptblocks.')]
[CmdletBinding()]
param(
    [string] $ChatModel,

    [string] $EmbeddingModel,

    [string] $AudioModel,

    [string] $AudioFile,

    [string[]] $Feature = '*',

    [switch] $ListFeature,

    [switch] $IncludeWebServer,

    [ValidateRange(1, 65535)]
    [int] $WebServerPort = 52495,

    [string] $BaselinePath,

    [string] $ResultsPath = (Join-Path $PSScriptRoot 'results'),

    [switch] $NoSave,

    [switch] $PassThru,

    [switch] $Force
)

$ErrorActionPreference = 'Stop'

$repoRoot     = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$manifestPath = Join-Path $repoRoot 'src/PwshFoundry/PwshFoundry.psd1'
if (-not $AudioFile) {
    $AudioFile = Join-Path $repoRoot 'samples/Recording.mp3'
}

#region Harness

$script:Features = [System.Collections.Generic.List[object]]::new()
$script:State    = @{}
$script:Info     = $null

# Registers a feature. The test scriptblock throws on failure and returns an ordered
# dictionary of stable facts (the observation) that is compared across CLI versions.
function Register-Feature {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Command,
        [Parameter(Mandatory)] [scriptblock] $Test,
        [scriptblock] $SkipWhen,
        [string] $SkipReason
    )
    $script:Features.Add([PSCustomObject]@{
        Name       = $Name
        Command    = $Command
        Test       = $Test
        SkipWhen   = $SkipWhen
        SkipReason = $SkipReason
    })
}

function Assert-True {
    param([Parameter(Mandatory)] [bool] $Condition, [Parameter(Mandatory)] [string] $Message)
    if (-not $Condition) {
        throw "Assertion failed: $Message"
    }
}

# Informational value shown in the report but never compared with the baseline.
function Add-Info {
    param([Parameter(Mandatory)] [string] $Name, $Value)
    $script:Info[$Name] = $Value
}

function Get-PropertyName {
    param($InputObject)
    if ($null -eq $InputObject) { return @() }
    if ($InputObject -is [System.Collections.IDictionary]) {
        return @($InputObject.Keys | ForEach-Object { "$_" } | Sort-Object)
    }
    return @($InputObject.PSObject.Properties.Name | Sort-Object)
}

function Get-ShortText {
    param([string] $Text, [int] $Length = 120)
    if (-not $Text) { return $Text }
    $flat = ($Text -replace '\s+', ' ').Trim()
    if ($flat.Length -le $Length) { return $flat }
    return $flat.Substring(0, $Length) + '...'
}

# Runs a scriptblock inside the module scope, to reach the private helpers.
function Invoke-InModule {
    param([Parameter(Mandatory)] [scriptblock] $ScriptBlock, [object[]] $ArgumentList = @())
    $module = Get-Module PwshFoundry
    & $module $ScriptBlock @ArgumentList
}

# Ids of the loaded models, read from the REST API directly so that model management
# tests do not depend on Get-FoundryModelCache.
function Get-LoadedModelId {
    $loaded = Invoke-InModule { Invoke-FoundryApiRequest -Action 'models-loaded' -Method GET }
    return , @($loaded | ForEach-Object { $_ } | Where-Object { $_ } | ForEach-Object { "$_" })
}

function Invoke-Feature {
    param([Parameter(Mandatory)] $Definition)

    $script:Info = [ordered]@{}
    $result = [ordered]@{
        Feature     = $Definition.Name
        Command     = $Definition.Command
        Status      = 'Pass'
        Regression  = $false
        Differences = @()
        Error       = $null
        DurationMs  = 0
        Observation = $null
        Info        = $null
    }

    if ($Definition.SkipWhen -and (& $Definition.SkipWhen)) {
        $result.Status = 'Skip'
        $result.Error  = $Definition.SkipReason
        return [PSCustomObject]$result
    }

    Write-Host ("  {0,-28}" -f $Definition.Name) -NoNewline
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        # Merge the error and warning streams so that non-terminating errors and CLI
        # warnings (stderr) are captured instead of being lost.
        $output = @(& $Definition.Test 2>&1 3>&1)

        $errors   = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
        $warnings = @($output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
        $observed = $output | Where-Object { $_ -is [System.Collections.IDictionary] } | Select-Object -Last 1

        if (-not $observed) { $observed = [ordered]@{} }
        if ($warnings) {
            $observed['Warnings'] = @($warnings | ForEach-Object { "$_" } | Sort-Object -Unique)
        }
        $result.Observation = $observed

        if ($errors) {
            throw "Non-terminating error: $($errors[0])"
        }
    }
    catch {
        $result.Status = 'Fail'
        # 'throw "text"' uses the text as error id; only show ids set by the module.
        $id = $_.FullyQualifiedErrorId
        $message = ($_.Exception.Message -replace '\s+', ' ').Trim()
        $result.Error  = if ($id -and $id -ne $_.Exception.Message -and $id -notmatch '^RuntimeException') {
            "[$id] $message"
        } else {
            $message
        }
    }
    finally {
        $watch.Stop()
    }

    $result.DurationMs = [int]$watch.ElapsedMilliseconds
    $result.Info       = $script:Info

    $color = if ($result.Status -eq 'Pass') { 'Green' } else { 'Red' }
    Write-Host ("{0,-5} {1,8:N0} ms" -f $result.Status, $result.DurationMs) -ForegroundColor $color

    return [PSCustomObject]$result
}

# Compares two observations key by key and returns a list of human readable differences.
function Compare-Observation {
    param($Baseline, $Current)

    # Round-trip both sides through JSON so that types match (int vs long, dictionary vs object).
    $toMap = {
        param($Value)
        $map = @{}
        if ($null -eq $Value) { return $map }
        $normalized = ConvertTo-Json -InputObject $Value -Depth 6 | ConvertFrom-Json
        foreach ($p in $normalized.PSObject.Properties) {
            $map[$p.Name] = ConvertTo-Json -InputObject $p.Value -Depth 6 -Compress
        }
        return $map
    }
    $baseMap    = & $toMap $Baseline
    $currentMap = & $toMap $Current

    $differences = foreach ($key in @(@($baseMap.Keys) + @($currentMap.Keys) | Sort-Object -Unique)) {
        $old = $baseMap[$key]
        $new = $currentMap[$key]
        if ($old -ceq $new) { continue }

        if ($null -eq $old)     { "$key added: $new" }
        elseif ($null -eq $new) { "$key removed (was $old)" }
        else                    { "${key}: $old -> $new" }
    }
    return , @($differences | Where-Object { $_ })
}

function Get-BaselineFile {
    param([string] $Folder, [string] $CurrentVersion)

    if (-not (Test-Path $Folder)) { return $null }

    $candidates = Get-ChildItem -Path $Folder -Filter 'foundry-*.json' | ForEach-Object {
        $raw = $_.BaseName -replace '^foundry-', ''
        $parsed = $null
        if ([version]::TryParse($raw, [ref]$parsed) -and $raw -ne $CurrentVersion) {
            [PSCustomObject]@{ Version = $parsed; File = $_ }
        }
    }
    if (-not $candidates) { return $null }

    $current = [version]$CurrentVersion
    $lower = $candidates | Where-Object Version -LT $current | Sort-Object Version -Descending | Select-Object -First 1
    $pick  = $lower ?? ($candidates | Sort-Object Version -Descending | Select-Object -First 1)
    return $pick.File.FullName
}

function Select-CatalogModel {
    param([object[]] $Catalog, [string] $Requested, [string[]] $Preferred, [scriptblock] $Fallback)

    if ($Requested) { return $Requested }
    foreach ($name in $Preferred) {
        $hit = $Catalog | Where-Object {
            $_.cached -and ($_.alias -eq $name -or ($_.id -split ':')[0] -eq $name)
        } | Select-Object -First 1
        if ($hit) { return ($hit.id -split ':')[0] }
    }
    $hit = $Catalog | Where-Object { $_.cached } | Where-Object $Fallback | Select-Object -First 1
    if ($hit) { return ($hit.id -split ':')[0] }
    return $null
}

#endregion

#region Features

Register-Feature -Name 'CliVersion' -Command 'Get-FoundryVersion' -Test {
    $v = Get-FoundryVersion -ByPassCache
    Assert-True ($v.Source -eq 'CLI') "Source is 'CLI' (got '$($v.Source)')"
    Assert-True ($v.Version -match '^\d+\.\d+\.\d+$') "Version is MAJOR.MINOR.PATCH (got '$($v.Version)')"
    Add-Info 'Message' $v.Message
    [ordered]@{
        Source        = $v.Source
        PropertyNames = Get-PropertyName $v
    }
}

Register-Feature -Name 'ServicePort' -Command 'Get-FoundryServicePort (private, foundry server status)' -Test {
    $port = Invoke-InModule { Get-FoundryServicePort }
    Assert-True ($port -is [int] -and $port -gt 0) "a positive port is parsed from 'foundry server status' (got '$port')"
    Add-Info 'Port' $port
    [ordered]@{ PortType = $port.GetType().Name }
}

Register-Feature -Name 'CliModelListJson' -Command 'foundry model list --output json (private Invoke-FoundryCli)' -Test {
    $raw = Invoke-InModule { Invoke-FoundryCli -Arguments @('model', 'list') -Json }
    $models = if ($raw.models) { @($raw.models) } else { @($raw) }
    Assert-True ($models.Count -gt 0) 'the CLI returns at least one model'

    $entryKeys = @($models | ForEach-Object { $_.PSObject.Properties.Name } | Sort-Object -Unique)
    $missing = @('alias', 'id', 'cached', 'type', 'device') | Where-Object { $_ -notin $entryKeys }
    Assert-True (-not $missing) "model entries expose alias, id, cached, type, device (missing: $($missing -join ', '))"

    Add-Info 'ModelCount' $models.Count
    Add-Info 'Types' (@($models.type | Sort-Object -Unique) -join ', ')
    Add-Info 'Devices' (@($models.device | Sort-Object -Unique) -join ', ')
    [ordered]@{
        TopLevelKeys       = Get-PropertyName $raw
        EntryKeys          = $entryKeys
        IdsHaveVersionTag  = [bool](-not ($models | Where-Object { $_.id -notmatch ':\d+$' }))
    }
}

Register-Feature -Name 'ModelList' -Command 'Get-FoundryModelList' -Test {
    $list = @(Get-FoundryModelList -ByPassCache)
    Assert-True ($list.Count -gt 0) 'the catalog is not empty'
    Assert-True (-not ($list | Where-Object { -not $_.id })) 'every model has an id'
    Assert-True (-not ($list | Where-Object { -not $_.alias })) 'every model has an alias'
    Assert-True ([bool]($list | Where-Object cached)) 'at least one model is cached'

    $cached = @($list | Where-Object { $_.cached -eq $true })
    Add-Info 'Count' $list.Count
    Add-Info 'Cached' $cached.Count
    [ordered]@{
        PropertyNames       = Get-PropertyName $list[0]
        CachedType          = $list[0].cached.GetType().Name
        ToolCallingReported = [bool]($list | Where-Object { $null -ne $_.supportsToolCalling })
    }
}

Register-Feature -Name 'ModelResolve' -Command 'Resolve-FoundryModel (private, alias/id/versioned id)' -SkipWhen {
    -not $script:State.ChatEntry
} -SkipReason 'No chat model available' -Test {
    $entry = $script:State.ChatEntry
    $byAlias     = @(Invoke-InModule { param($n) Resolve-FoundryModel -Name $n } $entry.alias)
    $byId        = @(Invoke-InModule { param($n) Resolve-FoundryModel -Name $n } ($entry.id -split ':')[0])
    $byVersioned = @(Invoke-InModule { param($n) Resolve-FoundryModel -Name $n } $entry.id)
    $isValid     = Invoke-InModule { param($n) Test-FoundryModelName -ModelName $n } ($entry.id -split ':')[0]

    Assert-True ($byAlias.Count -gt 0) "alias '$($entry.alias)' resolves"
    Assert-True ($byId.Count -gt 0) "id '$(($entry.id -split ':')[0])' resolves"
    Assert-True ($byVersioned.Count -gt 0) "versioned id '$($entry.id)' resolves"
    Assert-True $isValid 'Test-FoundryModelName accepts the unversioned id'
    [ordered]@{
        AliasResolves     = $byAlias.Count -gt 0
        IdResolves        = $byId.Count -gt 0
        VersionedResolves = $byVersioned.Count -gt 0
    }
}

Register-Feature -Name 'Status' -Command 'Get-FoundryStatus' -Test {
    $status = Get-FoundryStatus
    Assert-True ($null -ne $status) 'the status endpoint returns a value'
    Add-Info 'Status' (Get-ShortText ($status | ConvertTo-Json -Depth 4 -Compress) 200)
    [ordered]@{
        ReturnType    = $status.GetType().Name
        PropertyNames = Get-PropertyName $status
    }
}

Register-Feature -Name 'ApiModelList' -Command "Invoke-FoundryApiRequest -Action model-list (private)" -Test {
    $response = Invoke-InModule { Invoke-FoundryApiRequest -Action 'model-list' -Method GET }
    Assert-True ($null -ne $response) 'the model-list route answers'
    $first = if ($response.data) { @($response.data)[0] } else { @($response)[0] }
    [ordered]@{
        PropertyNames = Get-PropertyName $response
        EntryKeys     = Get-PropertyName $first
    }
}

Register-Feature -Name 'ModelUnload' -Command "Invoke-FoundryApiRequest -Action model-unload (private)" -SkipWhen {
    -not $script:State.ChatEntry
} -SkipReason 'No chat model available' -Test {
    $entry = $script:State.ChatEntry
    $before = Get-LoadedModelId
    if ($entry.id -notin $before) {
        $null = Invoke-InModule { param($n) Invoke-FoundryApiRequest -Action 'model-load' -Method GET -PathParameters @{ name = $n } } $entry.alias
    }
    $response = Invoke-InModule { param($n) Invoke-FoundryApiRequest -Action 'model-unload' -Method GET -PathParameters @{ name = $n } } $entry.alias
    $after = Get-LoadedModelId
    Assert-True ($entry.id -notin $after) "'$($entry.id)' is no longer loaded after unload by alias"
    [ordered]@{
        ResponseType = if ($null -ne $response) { $response.GetType().Name } else { $null }
        Unloaded     = $entry.id -notin $after
    }
}

Register-Feature -Name 'ModelCacheEmpty' -Command 'Get-FoundryModelCache (no model loaded)' -SkipWhen {
    (Get-LoadedModelId).Count -gt 0
} -SkipReason 'Other models are still loaded in the service' -Test {
    $loaded = @(Get-FoundryModelCache)
    Assert-True ($loaded.Count -eq 0) "returns nothing when no model is loaded (got $($loaded.Count))"
    [ordered]@{ Count = $loaded.Count }
}

Register-Feature -Name 'ChatAutoLoad' -Command 'New-FoundryChat (model not loaded)' -SkipWhen {
    -not $script:State.ChatModel
} -SkipReason 'No chat model available' -Test {
    $msg  = New-FoundryMessage -UserPrompt 'Reply with the single word: ready'
    $chat = New-FoundryChat -Message $msg -Model $script:State.ChatModel -MaxTokens 16 -Temperature 0 `
        -LogFilePath $script:State.LogFile
    Assert-True (-not [string]::IsNullOrWhiteSpace($chat.message.content)) 'the model answers after being loaded on demand'
    $loaded = Get-LoadedModelId
    Assert-True ($script:State.ChatEntry.id -in $loaded) 'the model is loaded after the call'
    Add-Info 'Answer' (Get-ShortText $chat.message.content)
    [ordered]@{ LoadedAfterCall = $script:State.ChatEntry.id -in $loaded }
}

Register-Feature -Name 'DeployModel' -Command 'Deploy-FoundryModel' -SkipWhen {
    -not $script:State.ChatEntry
} -SkipReason 'No chat model available' -Test {
    $response = Deploy-FoundryModel -Model $script:State.ChatEntry.alias
    $loaded = Get-LoadedModelId
    Assert-True ($script:State.ChatEntry.id -in $loaded) "'$($script:State.ChatEntry.id)' is loaded"
    [ordered]@{
        ResponseType = if ($null -ne $response) { $response.GetType().Name } else { $null }
        Loaded       = $script:State.ChatEntry.id -in $loaded
    }
}

Register-Feature -Name 'ModelCache' -Command 'Get-FoundryModelCache (model loaded)' -Test {
    $loaded = @(Get-FoundryModelCache)
    Assert-True ($loaded.Count -gt 0) 'lists at least one loaded model'
    if ($script:State.ChatEntry) {
        Assert-True ($script:State.ChatEntry.id -in $loaded) "lists '$($script:State.ChatEntry.id)'"
    }
    Add-Info 'Loaded' ($loaded -join ', ')
    [ordered]@{
        ElementType       = $loaded[0].GetType().Name
        IdsHaveVersionTag = [bool](-not ($loaded | Where-Object { "$_" -notmatch ':\d+$' }))
    }
}

Register-Feature -Name 'SaveModelCached' -Command 'Save-FoundryModel (already cached)' -SkipWhen {
    -not $script:State.ChatEntry
} -SkipReason 'No chat model available' -Test {
    $saved = Save-FoundryModel -ModelID $script:State.ChatEntry.alias -Confirm:$false
    Assert-True ($null -ne $saved) 'returns a result object'
    Assert-True ($saved.Downloaded -eq $false) 'a cached model is not downloaded again'
    Assert-True ($saved.Alias -eq $script:State.ChatEntry.alias) "Alias is '$($script:State.ChatEntry.alias)' (got '$($saved.Alias)')"
    Assert-True ($saved.Id -match ':\d+$') "Id is a versioned id (got '$($saved.Id)')"
    Add-Info 'Message' $saved.Message
    [ordered]@{
        PropertyNames         = Get-PropertyName $saved
        Downloaded            = $saved.Downloaded
        Loaded                = $saved.Loaded
        MessageNamesQuotedId  = [bool]($saved.Message -match "'[^']+:\d+'")
    }
}

Register-Feature -Name 'SaveModelUnknown' -Command 'Save-FoundryModel (unknown model)' -Test {
    $errorId = $null
    try {
        $null = Save-FoundryModel -ModelID 'pwshfoundry-no-such-model' -Confirm:$false
    } catch {
        $errorId = $_.FullyQualifiedErrorId
    }
    Assert-True ($errorId -like 'FoundryModelNotFound*') "throws FoundryModelNotFound (got '$errorId')"
    [ordered]@{ ErrorId = ($errorId -split ',')[0] }
}

Register-Feature -Name 'ChatMessage' -Command 'New-FoundryMessage + New-FoundryChat' -SkipWhen {
    -not $script:State.ChatModel
} -SkipReason 'No chat model available' -Test {
    $msg = New-FoundryMessage -UserPrompt 'What is the capital of France? Answer in one word.' `
        -SystemPrompt 'You are a concise assistant.'
    Assert-True ($msg.GetType().Name -eq 'FoundryMessage') 'New-FoundryMessage returns a FoundryMessage'
    $chat = New-FoundryChat -Message $msg -Model $script:State.ChatModel -Temperature 0 -MaxTokens 32 -TopP 0.9 `
        -LogFilePath $script:State.LogFile
    Assert-True (-not [string]::IsNullOrWhiteSpace($chat.message.content)) 'the answer is not empty'
    Assert-True ($chat.message.role -eq 'assistant') "message role is 'assistant' (got '$($chat.message.role)')"
    Add-Info 'Answer' (Get-ShortText $chat.message.content)
    Add-Info 'Model' $chat.model
    [ordered]@{
        ResultProperties = Get-PropertyName $chat
        MessageKeys      = Get-PropertyName $chat.message
        UsageKeys        = Get-PropertyName $chat.usage
        Object           = $chat.object
        ModelIsVersioned = [bool]($chat.model -match ':\d+$')
        FinishReason     = $chat.finish_reason
    }
}

Register-Feature -Name 'ChatMaxTokens' -Command 'New-FoundryChat -MaxTokens' -SkipWhen {
    -not $script:State.ChatModel
} -SkipReason 'No chat model available' -Test {
    $msg  = New-FoundryMessage -UserPrompt 'Write a long essay about the history of computing.'
    $chat = New-FoundryChat -Message $msg -Model $script:State.ChatModel -MaxTokens 8 -LogFilePath $script:State.LogFile
    $completion = $chat.usage.completion_tokens
    Add-Info 'CompletionTokens' $completion
    Assert-True ($null -ne $completion -and $completion -le 8) "completion_tokens <= 8 (got '$completion')"
    [ordered]@{
        FinishReason    = $chat.finish_reason
        LimitHonored    = $completion -le 8
    }
}

Register-Feature -Name 'ChatCountToken' -Command 'New-FoundryChat -CountTokenOnly' -SkipWhen {
    -not $script:State.ChatModel
} -SkipReason 'No chat model available' -Test {
    $msg   = New-FoundryMessage -UserPrompt 'Say hi.'
    $usage = New-FoundryChat -Message $msg -Model $script:State.ChatModel -MaxTokens 8 -CountTokenOnly `
        -LogFilePath $script:State.LogFile
    Assert-True ($usage.prompt_tokens -gt 0) "prompt_tokens > 0 (got '$($usage.prompt_tokens)')"
    Add-Info 'PromptTokens' $usage.prompt_tokens
    [ordered]@{ UsageKeys = Get-PropertyName $usage }
}

Register-Feature -Name 'ChatContext' -Command 'New-FoundryChatContext + New-FoundryChat -Context' -SkipWhen {
    -not $script:State.ChatModel
} -SkipReason 'No chat model available' -Test {
    $ctx = New-FoundryChatContext -UserPrompt 'My name is Ada. Reply with OK.' -SystemPrompt 'You are terse.'
    $null = New-FoundryChat -Context $ctx -Model $script:State.ChatModel -Temperature 0 -MaxTokens 16 `
        -LogFilePath $script:State.LogFile
    $ctx.AddUserPrompt('What is my name? Answer with the name only.')
    $second = New-FoundryChat -Context $ctx -Model $script:State.ChatModel -Temperature 0 -MaxTokens 16 `
        -LogFilePath $script:State.LogFile
    $roles = @($ctx.GetMessages() | ForEach-Object { $_.role })
    Assert-True ($roles.Count -eq 5) "context holds 5 messages after 2 turns (got $($roles.Count): $($roles -join ','))"
    Add-Info 'SecondAnswer' (Get-ShortText $second.message.content)
    [ordered]@{
        Roles          = $roles
        RemembersName  = [bool]($second.message.content -match 'Ada')
    }
}

Register-Feature -Name 'ChatTools' -Command 'New-FoundryTool + New-FoundryChat -Tools -ToolChoice' -SkipWhen {
    -not $script:State.ChatModel
} -SkipReason 'No chat model available' -Test {
    $script:ToolProbe = @{ Called = 0; Arguments = @() }
    $tool = New-FoundryTool -Name 'Get-CityTemperature' -Description 'Returns the current temperature of a city' `
        -Parameters @{ City = @{ type = 'string'; description = 'Name of the city' } } -Required 'City' `
        -Handler {
            param($City)
            $script:ToolProbe.Called++
            $script:ToolProbe.Arguments = @($PSBoundParameters.Keys)
            "The temperature in $City is 21 degrees Celsius."
        }
    Assert-True ($tool.GetType().Name -eq 'FoundryTool') 'New-FoundryTool returns a FoundryTool'

    $ctx  = New-FoundryChatContext -UserPrompt 'What is the temperature in Paris?'
    $chat = New-FoundryChat -Context $ctx -Model $script:State.ChatModel -Tools $tool `
        -ToolChoice 'Get-CityTemperature' -MaxTokens 128 -Temperature 0 -LogFilePath $script:State.LogFile
    Assert-True ($script:ToolProbe.Called -gt 0) 'the tool handler is invoked'
    Add-Info 'Answer' (Get-ShortText $chat.message.content)
    Add-Info 'HandlerCalls' $script:ToolProbe.Called
    [ordered]@{
        ToolInvoked      = $script:ToolProbe.Called -gt 0
        ArgumentsPassed  = @($script:ToolProbe.Arguments | Sort-Object)
        ContextRoles     = @($ctx.GetMessages() | ForEach-Object { $_.role })
        FinalFinish      = $chat.finish_reason
        AnswerMentions21 = [bool]($chat.message.content -match '21')
    }
}

Register-Feature -Name 'ChatErrors' -Command 'New-FoundryChat (unknown model, bad ToolChoice, bad log path)' -SkipWhen {
    -not $script:State.ChatModel
} -SkipReason 'No chat model available' -Test {
    $msg = New-FoundryMessage -UserPrompt 'hi'
    $ids = [ordered]@{}

    try { $null = New-FoundryChat -Message $msg -Model 'pwshfoundry-no-such-model' }
    catch { $ids.UnknownModel = ($_.FullyQualifiedErrorId -split ',')[0] }

    $tool = New-FoundryTool -Name 'Noop' -Description 'Does nothing' -Handler { 'ok' }
    try { $null = New-FoundryChat -Message $msg -Model $script:State.ChatModel -Tools $tool -ToolChoice 'Other' }
    catch { $ids.InvalidToolChoice = ($_.FullyQualifiedErrorId -split ',')[0] }

    try { $null = New-FoundryChat -Message $msg -Model $script:State.ChatModel -LogFilePath 'Z:\no\such\dir\log.jsonl' }
    catch { $ids.InvalidLogPath = ($_.FullyQualifiedErrorId -split ',')[0] }

    Assert-True ($ids.UnknownModel -eq 'FoundryModelNotFound') "unknown model -> FoundryModelNotFound (got '$($ids.UnknownModel)')"
    Assert-True ($ids.InvalidToolChoice -eq 'FoundryInvalidToolChoice') "bad ToolChoice -> FoundryInvalidToolChoice (got '$($ids.InvalidToolChoice)')"
    Assert-True ($ids.InvalidLogPath -eq 'FoundryInvalidLogFilePath') "bad log path -> FoundryInvalidLogFilePath (got '$($ids.InvalidLogPath)')"
    $ids
}

Register-Feature -Name 'ChatLogFile' -Command 'New-FoundryChat -LogFilePath' -SkipWhen {
    -not $script:State.ChatModel
} -SkipReason 'No chat model available' -Test {
    Assert-True (Test-Path $script:State.LogFile) "the chat log file '$($script:State.LogFile)' was written"
    $entries = @(Get-Content $script:State.LogFile | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json })
    Assert-True ($entries.Count -gt 0) 'the log contains entries'
    Add-Info 'Entries' $entries.Count
    [ordered]@{ EntryKeys = Get-PropertyName $entries[-1] }
}

Register-Feature -Name 'EmbeddingSingle' -Command 'New-FoundryEmbedding -Text' -SkipWhen {
    -not $script:State.EmbeddingModel
} -SkipReason 'No embedding model available' -Test {
    $e = @(New-FoundryEmbedding -Model $script:State.EmbeddingModel -Text 'PowerShell is a shell and scripting language')
    Assert-True ($e.Count -eq 1) "one result for one text (got $($e.Count))"
    Assert-True ($e[0].Embedding.Count -gt 0) 'the vector is not empty'
    $script:State.EmbeddingRef = $e[0]
    Add-Info 'Model' $e[0].Model
    [ordered]@{
        PropertyNames = Get-PropertyName $e[0]
        Dimension     = $e[0].Embedding.Count
        UsageKeys     = Get-PropertyName $e[0].Usage
    }
}

Register-Feature -Name 'EmbeddingBatch' -Command 'New-FoundryEmbedding (pipeline batch)' -SkipWhen {
    -not $script:State.EmbeddingModel
} -SkipReason 'No embedding model available' -Test {
    $texts = 'The cat sat on the mat', 'A feline rested on the rug', 'Quarterly revenue grew by ten percent'
    $e = @($texts | New-FoundryEmbedding -Model $script:State.EmbeddingModel)
    Assert-True ($e.Count -eq 3) "three results for three texts (got $($e.Count))"
    Assert-True ((@($e.Index) -join ',') -eq '0,1,2') "results are ordered by index (got $(@($e.Index) -join ','))"
    Assert-True ((@($e.Text) -join '|') -eq ($texts -join '|')) 'each result carries its source text'
    $script:State.EmbeddingBatch = $e
    [ordered]@{
        Count        = $e.Count
        SameDimension = [bool](@($e | ForEach-Object { $_.Embedding.Count } | Sort-Object -Unique).Count -eq 1)
    }
}

Register-Feature -Name 'CompareEmbedding' -Command 'Compare-FoundryEmbedding' -SkipWhen {
    -not $script:State.EmbeddingModel
} -SkipReason 'No embedding model available' -Test {
    $e = $script:State.EmbeddingBatch
    Assert-True ($null -ne $e -and $e.Count -eq 3) 'EmbeddingBatch produced vectors'
    $similar    = Compare-FoundryEmbedding -ReferenceEmbedding $e[0] -DifferenceEmbedding $e[1]
    $dissimilar = Compare-FoundryEmbedding -ReferenceEmbedding $e[0] -DifferenceEmbedding $e[2]
    $self       = Compare-FoundryEmbedding -ReferenceEmbedding $e[0] -DifferenceEmbedding $e[0].Embedding
    Assert-True ([math]::Abs($self - 1) -lt 1e-6) "self similarity is 1 (got $self)"
    Assert-True ($similar -gt $dissimilar) "similar sentences score higher ($similar) than unrelated ones ($dissimilar)"
    Add-Info 'Similar' ([math]::Round($similar, 4))
    Add-Info 'Dissimilar' ([math]::Round($dissimilar, 4))
    [ordered]@{
        ReturnType         = $similar.GetType().Name
        SimilarRankedFirst = $similar -gt $dissimilar
    }
}

Register-Feature -Name 'AudioText' -Command 'New-FoundryAudioTranscription' -SkipWhen {
    -not $script:State.AudioModel -or -not (Test-Path $script:State.AudioFile)
} -SkipReason 'No speech model or audio file available' -Test {
    $text = New-FoundryAudioTranscription -ModelId $script:State.AudioModel -AudioFile $script:State.AudioFile `
        -LogFilePath $script:State.LogFile
    Assert-True ($text -is [string]) "returns a string (got '$($text.GetType().Name)')"
    Assert-True (-not [string]::IsNullOrWhiteSpace($text)) 'the transcription is not empty'
    Add-Info 'Text' (Get-ShortText $text)
    [ordered]@{
        ReturnType = $text.GetType().Name
        Trimmed    = $text -eq $text.Trim()
    }
}

Register-Feature -Name 'AudioJson' -Command 'New-FoundryAudioTranscription -ResponseFormat json -Language' -SkipWhen {
    -not $script:State.AudioModel -or -not (Test-Path $script:State.AudioFile)
} -SkipReason 'No speech model or audio file available' -Test {
    $r = New-FoundryAudioTranscription -ModelId $script:State.AudioModel -AudioFile $script:State.AudioFile `
        -Language 'en' -Temperature 0 -ResponseFormat json -LogFilePath $script:State.LogFile
    Assert-True (-not [string]::IsNullOrWhiteSpace($r.Text)) 'Text is not empty'
    Assert-True ($r.Model -match ':\d+$') "Model is the versioned id (got '$($r.Model)')"
    Add-Info 'Model' $r.Model
    [ordered]@{
        PropertyNames = Get-PropertyName $r
        Language      = $r.Language
        HasId         = -not [string]::IsNullOrWhiteSpace($r.Id)
    }
}

Register-Feature -Name 'AudioErrors' -Command 'New-FoundryAudioTranscription (missing file, unknown model)' -Test {
    $ids = [ordered]@{}
    try { $null = New-FoundryAudioTranscription -ModelId 'whisper-tiny' -AudioFile 'Z:\no\such\file.mp3' }
    catch { $ids.MissingFile = ($_.FullyQualifiedErrorId -split ',')[0] }

    $file = $script:State.AudioFile
    if (Test-Path $file) {
        try { $null = New-FoundryAudioTranscription -ModelId 'whisper-pwshfoundry-none' -AudioFile $file }
        catch { $ids.UnknownModel = ($_.FullyQualifiedErrorId -split ',')[0] }
        Assert-True ($ids.UnknownModel -eq 'FoundryModelNotFound') "unknown model -> FoundryModelNotFound (got '$($ids.UnknownModel)')"
    }
    Assert-True ($ids.MissingFile -eq 'AudioFileNotFound') "missing file -> AudioFileNotFound (got '$($ids.MissingFile)')"
    $ids
}

Register-Feature -Name 'WebServer' -Command 'Start-FoundryWebServer + Stop-FoundryWebServer (SDK)' -SkipWhen {
    -not $IncludeWebServer -or -not $script:State.ChatEntry
} -SkipReason 'Opt-in: use -IncludeWebServer' -Test {
    $server = Start-FoundryWebServer -ModelAlias $script:State.ChatEntry.alias -Port $WebServerPort
    try {
        Assert-True ($server.Endpoint -match '^http://') "returns an endpoint (got '$($server.Endpoint)')"
        $models = Invoke-RestMethod -Uri "$($server.Endpoint)/models" -Method GET -TimeoutSec 30
        Add-Info 'Endpoint' $server.Endpoint
        Add-Info 'ModelId' $server.ModelId
        $observation = [ordered]@{
            PropertyNames   = Get-PropertyName $server
            ModelsRouteKeys = Get-PropertyName $models
        }
    }
    finally {
        Stop-FoundryWebServer
    }
    $process = Get-Process -Id $server.ProcessId -ErrorAction SilentlyContinue
    Assert-True ($null -eq $process) 'the server process is stopped'
    $observation
}

#endregion

#region Main

if ($ListFeature) {
    $script:Features | Select-Object Name, Command
    return
}

if (($env:CI -or $env:GITHUB_ACTIONS -or $env:TF_BUILD) -and -not $Force) {
    throw 'CI environment detected. This script needs a local Foundry install and real models; use -Force to run anyway.'
}

Import-Module $manifestPath -Force

$versionInfo = Get-FoundryVersion -ByPassCache
if ($versionInfo.Source -ne 'CLI' -or -not $versionInfo.Version) {
    throw "The Foundry CLI was not found or its version could not be parsed ($($versionInfo.Message))."
}
$cliVersion = $versionInfo.Version

$runDir = Join-Path ([System.IO.Path]::GetTempPath()) "PwshFoundryCompat_$(Get-Date -Format 'yyyyMMddHHmmss')"
$null = New-Item -ItemType Directory -Path $runDir

Write-Host ''
Write-Host "PwshFoundry compatibility test - Foundry CLI $cliVersion" -ForegroundColor Cyan

$catalog = @()
try {
    $catalog = @(Get-FoundryModelList -ByPassCache)
} catch {
    Write-Warning "Could not read the model catalog, model-based features will be skipped: $($_.Exception.Message)"
}

$script:State.ChatModel = Select-CatalogModel -Catalog $catalog -Requested $ChatModel `
    -Preferred 'qwen3-0.6b', 'phi-4-mini' -Fallback { $_.type -eq 'Chat' -and $_.supportsToolCalling }
$script:State.EmbeddingModel = Select-CatalogModel -Catalog $catalog -Requested $EmbeddingModel `
    -Preferred 'qwen3-embedding-0.6b' -Fallback { $_.type -eq 'Embedding' }
$script:State.AudioModel = Select-CatalogModel -Catalog $catalog -Requested $AudioModel `
    -Preferred 'whisper-tiny', 'whisper-small' -Fallback { $_.type -eq 'Speech' }
$script:State.AudioFile = $AudioFile
$script:State.LogFile   = Join-Path $runDir 'chat-log.jsonl'

if ($script:State.ChatModel) {
    $script:State.ChatEntry = $catalog | Where-Object {
        $_.id -eq $script:State.ChatModel -or ($_.id -split ':')[0] -eq $script:State.ChatModel -or
        $_.alias -eq $script:State.ChatModel
    } | Sort-Object { -not $_.cached } | Select-Object -First 1
    if ($script:State.ChatEntry) {
        # New-FoundryChat validates ids, not aliases: always pass the unversioned id.
        $script:State.ChatModel = ($script:State.ChatEntry.id -split ':')[0]
    }
}

$models = [ordered]@{
    Chat      = $script:State.ChatModel
    Embedding = $script:State.EmbeddingModel
    Audio     = $script:State.AudioModel
}
Write-Host ("Models: chat={0}  embedding={1}  audio={2}" -f $models.Chat, $models.Embedding, $models.Audio)
Write-Host ''

# 'pwsh -File' passes 'A,B' as a single string.
$Feature = @($Feature -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$selected = @($script:Features | Where-Object {
    $name = $_.Name
    [bool]($Feature | Where-Object { $name -like $_ })
})
if (-not $selected) {
    throw "No feature matches '$($Feature -join ', ')'. Use -ListFeature to list them."
}

$results = foreach ($definition in $selected) {
    Invoke-Feature -Definition $definition
}

# Compare with the baseline.
$baselineFile = if ($BaselinePath) { $BaselinePath } else { Get-BaselineFile -Folder $ResultsPath -CurrentVersion $cliVersion }
$baseline = $null
if ($baselineFile) {
    if (-not (Test-Path $baselineFile)) {
        throw "Baseline file '$baselineFile' does not exist."
    }
    $baseline = Get-Content $baselineFile -Raw | ConvertFrom-Json
}

$modelsChanged = $false
if ($baseline) {
    $modelsChanged = ($baseline.Models | ConvertTo-Json -Compress) -ne ($models | ConvertTo-Json -Compress)

    foreach ($result in $results) {
        $previous = $baseline.Results | Where-Object Feature -eq $result.Feature | Select-Object -First 1
        if (-not $previous -or $result.Status -eq 'Skip' -or $previous.Status -eq 'Skip') { continue }

        if ($result.Status -eq 'Fail') {
            $result.Regression = $previous.Status -in 'Pass', 'Diff'
            continue
        }

        # A failed baseline has no meaningful observation: only report that it works now.
        $result.Differences = if ($previous.Status -eq 'Fail') {
            @("Fixed: failed on $($baseline.FoundryVersion)")
        } else {
            Compare-Observation -Baseline $previous.Observation -Current $result.Observation
        }
        if ($result.Differences.Count -gt 0) {
            $result.Status = 'Diff'
        }
    }
}

$report = [ordered]@{
    FoundryVersion = $cliVersion
    CliMessage     = $versionInfo.Message
    ModuleVersion  = (Import-PowerShellDataFile $manifestPath).ModuleVersion
    PowerShell     = $PSVersionTable.PSVersion.ToString()
    OS             = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
    Date           = (Get-Date).ToString('o')
    Baseline       = if ($baseline) { $baseline.FoundryVersion } else { $null }
    Models         = $models
    Summary        = [ordered]@{
        Pass = @($results | Where-Object Status -eq 'Pass').Count
        Diff = @($results | Where-Object Status -eq 'Diff').Count
        Fail = @($results | Where-Object Status -eq 'Fail').Count
        Skip = @($results | Where-Object Status -eq 'Skip').Count
        Regressions = @($results | Where-Object Regression).Count
    }
    Results        = @($results)
}

# Console report.
Write-Host ''
Write-Host "Foundry CLI $cliVersion  |  baseline: $($report.Baseline ?? 'none')" -ForegroundColor Cyan
if ($modelsChanged) {
    Write-Warning 'The models differ from the baseline run; some differences may come from the models, not the CLI.'
}
foreach ($result in $results) {
    $color = switch ($result.Status) { 'Pass' { 'Green' } 'Diff' { 'Yellow' } 'Fail' { 'Red' } default { 'DarkGray' } }
    $label = if ($result.Regression) { 'FAIL (regression)' } else { $result.Status.ToUpper() }
    Write-Host ("  {0,-18} {1,-20} {2}" -f $label, $result.Feature, $result.Command) -ForegroundColor $color
    if ($result.Error) {
        Write-Host "      $($result.Error)" -ForegroundColor $color
    }
    foreach ($difference in $result.Differences) {
        Write-Host "      ~ $difference" -ForegroundColor $color
    }
}
$s = $report.Summary
Write-Host ''
Write-Host ("Pass: {0}  Diff: {1}  Fail: {2} (regressions: {3})  Skip: {4}" -f $s.Pass, $s.Diff, $s.Fail, $s.Regressions, $s.Skip) `
    -ForegroundColor ($s.Fail ? 'Red' : ($s.Diff ? 'Yellow' : 'Green'))

if (-not $NoSave) {
    $null = New-Item -ItemType Directory -Path $ResultsPath -Force
    $jsonPath = Join-Path $ResultsPath "foundry-$cliVersion.json"
    $mdPath   = Join-Path $ResultsPath "foundry-$cliVersion.md"

    $report | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath -Encoding utf8

    $escape = { param($t) ("$t" -replace '\|', '\|' -replace '\r?\n', ' ') }
    $md = [System.Text.StringBuilder]::new()
    $null = $md.AppendLine("# PwshFoundry compatibility - Foundry CLI $cliVersion").AppendLine()
    $null = $md.AppendLine("| | |").AppendLine("|---|---|")
    $null = $md.AppendLine("| Foundry CLI | $cliVersion |")
    $null = $md.AppendLine("| Baseline | $($report.Baseline ?? 'none') |")
    $null = $md.AppendLine("| Module | $($report.ModuleVersion) |")
    $null = $md.AppendLine("| PowerShell | $($report.PowerShell) |")
    $null = $md.AppendLine("| OS | $($report.OS) |")
    $null = $md.AppendLine("| Date | $($report.Date) |")
    $null = $md.AppendLine("| Models | chat: $($models.Chat), embedding: $($models.Embedding), audio: $($models.Audio) |")
    $null = $md.AppendLine().AppendLine("**Pass:** $($s.Pass) - **Diff:** $($s.Diff) - **Fail:** $($s.Fail) " +
        "(regressions: $($s.Regressions)) - **Skip:** $($s.Skip)").AppendLine()
    $null = $md.AppendLine('| Feature | Command | Status | Duration (ms) | Details |').AppendLine('|---|---|---|---|---|')
    foreach ($result in $results) {
        $status  = if ($result.Regression) { 'Fail (regression)' } else { $result.Status }
        $details = @()
        if ($result.Error) { $details += & $escape $result.Error }
        $details += $result.Differences | ForEach-Object { & $escape $_ }
        if ($result.Info) {
            $details += $result.Info.GetEnumerator() | ForEach-Object { & $escape "$($_.Key): $($_.Value)" }
        }
        $null = $md.AppendLine("| $($result.Feature) | $(& $escape $result.Command) | $status | $($result.DurationMs) | $($details -join '<br>') |")
    }
    Set-Content -Path $mdPath -Value $md.ToString() -Encoding utf8

    Write-Host "Results: $jsonPath"
    Write-Host "Report:  $mdPath"
}

Remove-Item -Path $runDir -Recurse -Force -ErrorAction SilentlyContinue

if ($PassThru) {
    $results
}

if ($s.Fail -gt 0) {
    exit 1
}

#endregion
