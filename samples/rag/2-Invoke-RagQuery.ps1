#Requires -Version 7.0

<#
    RAG - phase 2 of 2: answer questions (online).

    Runs the query side of the pipeline against the index built by 1-Build-RagIndex.ps1:

        embed question  ->  retrieve  ->  augment  ->  generate

    Run without -Question for an interactive loop.

    .EXAMPLE
        ./2-Invoke-RagQuery.ps1 -Question 'How long can a SecureLink Guest profile last?'
    .EXAMPLE
        # Show the exact prompt the model receives, and contrast with an ungrounded answer
        ./2-Invoke-RagQuery.ps1 -Question 'What is the on-call weekly rate?' -ShowContext -CompareWithoutRag
    .EXAMPLE
        # Interactive
        ./2-Invoke-RagQuery.ps1
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string] $Question,

    [Parameter()]
    [string] $IndexPath = "$PSScriptRoot/rag-index.json",

    [Parameter()]
    [string] $EmbeddingModel = 'qwen3-embedding-8b-generic-gpu',

    [Parameter()]
    [string] $ChatModel = 'qwen2.5-0.5b-instruct-generic-cpu',

    [Parameter()]
    [ValidateRange(1, 20)]
    [int] $TopN = 3,

    [Parameter()]
    [ValidateRange(0.0, 1.0)]
    [double] $MinScore = 0.3,

    [Parameter()]
    [switch] $ShowContext,

    [Parameter()]
    [switch] $CompareWithoutRag
)

Import-Module "$PSScriptRoot/../../src/PwshFoundry/PwshFoundry.psd1" -Force
Import-Module "$PSScriptRoot/RagHelpers.psm1" -Force

if (-not (Test-Path -Path $IndexPath)) {
    throw "Index '$IndexPath' not found. Run ./1-Build-RagIndex.ps1 first."
}

$index = Get-Content -Path $IndexPath -Raw | ConvertFrom-Json

# The query vector and the indexed vectors must come from the same model. Vectors
# from different models are not comparable, and cosine similarity will happily
# return plausible-looking nonsense rather than fail - so check it explicitly.
if ($index.embeddingModel -ne $EmbeddingModel) {
    throw ("Index was built with '{0}' but this query uses '{1}'. " -f $index.embeddingModel, $EmbeddingModel) +
          'Embeddings from different models are not comparable; rebuild the index or pass the matching -EmbeddingModel.'
}

Write-Output "Index: $($index.chunkCount) chunks, $($index.dimensions) dimensions, built $($index.createdUtc)"

function Invoke-RagQuestion {
    param(
        [Parameter(Mandatory)]
        [string] $UserQuestion
    )

    # -----------------------------------------------------------------------
    # STEP 1 - EMBED THE QUESTION
    #
    # The question is embedded with the same model as the corpus, putting it in
    # the same vector space so distances between them are meaningful.
    # -----------------------------------------------------------------------
    Write-Output ''
    Write-Output "=== QUESTION: $UserQuestion ==="
    Write-Output ''
    Write-Output '--- STEP 1: EMBED THE QUESTION ---'

    $queryEmbedding = New-FoundryEmbedding -Model $EmbeddingModel -Text $UserQuestion
    Write-Output "Question embedded as a $($queryEmbedding.Embedding.Count)-dimension vector."

    # -----------------------------------------------------------------------
    # STEP 2 - RETRIEVE
    #
    # Score every chunk against the question and keep the best few. The scores
    # are printed so it is visible *why* these chunks were chosen.
    # -----------------------------------------------------------------------
    Write-Output ''
    Write-Output '--- STEP 2: RETRIEVE ---'

    $retrieved = @(Get-RelevantChunk -QueryEmbedding $queryEmbedding -Chunk $index.chunks -TopN $TopN)

    # The preview is only the chunk's opening words - the matching fact often sits
    # further in. Use -ShowContext to read what the model is actually given.
    foreach ($match in $retrieved) {
        $preview = $match.Chunk.Text
        if ($preview.Length -gt 80) {
            $preview = $preview.Substring(0, 80) + '...'
        }
        Write-Output ("  #{0}  score {1:N4}  {2,-22} {3}" -f $match.Rank, $match.Score, $match.Chunk.Id, $preview)
    }

    # Retrieval gates the whole pipeline. If nothing scored well the honest answer
    # is "not in the documents" - calling the model here would only invite a guess.
    if ($retrieved[0].Score -lt $MinScore) {
        Write-Output ''
        Write-Output ("Best score {0:N4} is below the -MinScore threshold of {1:N2}." -f $retrieved[0].Score, $MinScore)
        Write-Output 'Nothing relevant was retrieved, so no answer is generated.'
        return
    }

    # -----------------------------------------------------------------------
    # STEP 3 - AUGMENT
    #
    # The retrieved text is pasted into the prompt as numbered blocks, with
    # instructions to use only those blocks and to cite them.
    # -----------------------------------------------------------------------
    Write-Output ''
    Write-Output '--- STEP 3: AUGMENT ---'

    $prompt = Build-GroundedPrompt -Question $UserQuestion -Context $retrieved

    $contextWords = ($prompt.UserPrompt -split '\s+').Count
    Write-Output "Built a grounded prompt of roughly $contextWords words from $($retrieved.Count) chunk(s)."

    if ($ShowContext) {
        Write-Output ''
        Write-Output '----- SYSTEM PROMPT -----'
        Write-Output $prompt.SystemPrompt
        Write-Output '----- USER PROMPT -----'
        Write-Output $prompt.UserPrompt
        Write-Output '-----------------------'
    }

    # -----------------------------------------------------------------------
    # STEP 4 - GENERATE
    #
    # Low temperature: this is a factual lookup, not creative writing.
    # -----------------------------------------------------------------------
    Write-Output ''
    Write-Output '--- STEP 4: GENERATE ---'

    $message = New-FoundryMessage -UserPrompt $prompt.UserPrompt -SystemPrompt $prompt.SystemPrompt
    $answer = New-FoundryChat -Message $message -Model $ChatModel -Temperature 0.1

    Write-Output ''
    Write-Output 'ANSWER (grounded):'
    Write-Output $answer.message.content
    Write-Output ''
    Write-Output "Sources: $(($retrieved.Chunk.Source | Select-Object -Unique) -join ', ')"

    # -----------------------------------------------------------------------
    # OPTIONAL - the same question with no retrieved context.
    #
    # The corpus describes an invented company, so the model has never seen these
    # facts. This contrast is the whole point of RAG.
    # -----------------------------------------------------------------------
    if ($CompareWithoutRag) {
        Write-Output ''
        Write-Output '--- CONTRAST: SAME QUESTION, NO RETRIEVAL ---'

        $bareMessage = New-FoundryMessage -UserPrompt $UserQuestion `
            -SystemPrompt 'You are a helpful assistant. Answer the question as best you can.'
        $bareAnswer = New-FoundryChat -Message $bareMessage -Model $ChatModel -Temperature 0.1

        Write-Output ''
        Write-Output 'ANSWER (no context):'
        Write-Output $bareAnswer.message.content
    }
}

if ($PSBoundParameters.ContainsKey('Question')) {
    Invoke-RagQuestion -UserQuestion $Question
    return
}

while ($true) {
    $userQuestion = Read-Host "`nAsk about Contoso policy (type 'exit' or 'quit' to end)"

    if ($userQuestion -in @('exit', 'quit')) {
        break
    }

    if ([string]::IsNullOrWhiteSpace($userQuestion)) {
        continue
    }

    Invoke-RagQuestion -UserQuestion $userQuestion
}
