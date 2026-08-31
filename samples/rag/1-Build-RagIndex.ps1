#Requires -Version 7.0

<#
    RAG - phase 1 of 2: build the index (offline).

    Turns a folder of markdown documents into a searchable vector index:

        ingest  ->  chunk  ->  embed  ->  store

    This phase is run once per corpus change, not once per question. Embedding is
    the slow, expensive part of RAG, so the vectors are computed here and saved;
    2-Invoke-RagQuery.ps1 then answers questions against the saved index.

    .EXAMPLE
        ./1-Build-RagIndex.ps1
    .EXAMPLE
        ./1-Build-RagIndex.ps1 -MaxWords 200 -OverlapWords 40 -Verbose
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string] $CorpusPath = "$PSScriptRoot/corpus",

    [Parameter()]
    [string] $IndexPath = "$PSScriptRoot/rag-index.json",

    [Parameter()]
    [string] $EmbeddingModel = 'qwen3-embedding-8b-generic-gpu',

    [Parameter()]
    [ValidateRange(20, 1000)]
    [int] $MaxWords = 120,

    [Parameter()]
    [ValidateRange(0, 200)]
    [int] $OverlapWords = 25,

    [Parameter()]
    [ValidateRange(1, 100)]
    [int] $BatchSize = 8
)

Import-Module "$PSScriptRoot/../../src/PwshFoundry/PwshFoundry.psd1" -Force
Import-Module "$PSScriptRoot/RagHelpers.psm1" -Force

# ---------------------------------------------------------------------------
# STEP 1 - INGEST: read the source documents
# ---------------------------------------------------------------------------
Write-Output '=== STEP 1: INGEST ==='

$documents = @(Get-ChildItem -Path $CorpusPath -Filter '*.md' -File)

if ($documents.Count -eq 0) {
    throw "No .md documents found in '$CorpusPath'."
}

Write-Output "Found $($documents.Count) document(s) in $CorpusPath"

# ---------------------------------------------------------------------------
# STEP 2 - CHUNK: split each document into passages small enough to embed well
#
# A whole document embedded as one vector averages every topic it covers and
# matches nothing precisely. Chunks keep one vector to roughly one idea.
# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '=== STEP 2: CHUNK ==='

# Collected into an explicit list rather than captured from the loop's output:
# the progress lines below would otherwise land in $chunks alongside the chunks.
$chunks = [System.Collections.Generic.List[object]]::new()

foreach ($document in $documents) {
    $text = Get-Content -Path $document.FullName -Raw
    $documentChunks = @(ConvertTo-DocumentChunk -Text $text -Source $document.Name `
                                                 -MaxWords $MaxWords -OverlapWords $OverlapWords)

    $chunks.AddRange([object[]] $documentChunks)
    Write-Output ("  {0,-28} {1,3} chunk(s)" -f $document.Name, $documentChunks.Count)
}
Write-Output "Total: $($chunks.Count) chunks (max $MaxWords words, $OverlapWords words overlap)"

# ---------------------------------------------------------------------------
# STEP 3 - EMBED: turn every chunk into a vector
#
# New-FoundryEmbedding takes an array and sends one request for the whole batch,
# which is far faster than one request per chunk. Batches are still bounded:
# a large batch on a large model can exceed the API request timeout (120s), so
# -BatchSize trades round trips against the risk of a timeout.
# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '=== STEP 3: EMBED ==='
Write-Output "Embedding $($chunks.Count) chunks with '$EmbeddingModel' in batches of $BatchSize"

# Warm-up on a single short text. The first request to a cold model pays for
# loading it into memory, and bundling that cost into the first real batch is
# enough to exceed the API's 120-second request timeout on a large model.
Write-Output '  warming up the model (loads it into memory)...'
$null = New-FoundryEmbedding -Model $EmbeddingModel -Text 'warm up'

$embedded = [System.Collections.Generic.List[object]]::new()

for ($offset = 0; $offset -lt $chunks.Count; $offset += $BatchSize) {
    $batch = @($chunks[$offset..([math]::Min($offset + $BatchSize - 1, $chunks.Count - 1))])

    Write-Output ("  embedding chunks {0}-{1} of {2}..." -f ($offset + 1), ($offset + $batch.Count), $chunks.Count)

    try {
        $embedded.AddRange([object[]] @(New-FoundryEmbedding -Model $EmbeddingModel -Text $batch.Text))
    }
    catch {
        throw ("Embedding failed for the batch starting at chunk {0}: {1} " -f ($offset + 1), $_.Exception.Message) +
              "If this was a timeout, re-run with a smaller -BatchSize."
    }
}

if ($embedded.Count -ne $chunks.Count) {
    throw "Expected $($chunks.Count) embeddings but received $($embedded.Count)."
}

$dimensions = $embedded[0].Embedding.Count
Write-Output "Done. Each chunk is now a vector of $dimensions dimensions."

# ---------------------------------------------------------------------------
# STEP 4 - STORE: persist chunks and vectors together
#
# The text has to be stored alongside the vector: retrieval finds the vector,
# but it is the text that gets pasted into the prompt later.
# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '=== STEP 4: STORE ==='

$indexedChunks = for ($i = 0; $i -lt $chunks.Count; $i++) {
    [PSCustomObject]@{
        Id        = $chunks[$i].Id
        Source    = $chunks[$i].Source
        Title     = $chunks[$i].Title
        Text      = $chunks[$i].Text
        WordCount = $chunks[$i].WordCount
        Embedding = $embedded[$i].Embedding
    }
}

$index = [PSCustomObject]@{
    createdUtc     = (Get-Date).ToUniversalTime().ToString('o')
    embeddingModel = $EmbeddingModel
    dimensions     = $dimensions
    maxWords       = $MaxWords
    overlapWords   = $OverlapWords
    chunkCount     = $chunks.Count
    chunks         = @($indexedChunks)
}

$index | ConvertTo-Json -Depth 6 -Compress | Set-Content -Path $IndexPath -Encoding utf8

$sizeMb = [math]::Round((Get-Item -Path $IndexPath).Length / 1MB, 2)

Write-Output "Index written to $IndexPath"
Write-Output "Size: $sizeMb MB for $($chunks.Count) chunks"
Write-Output ''
Write-Output "The vectors dominate that file: $($chunks.Count) x $dimensions numbers."
Write-Output "This is why real systems use a vector database instead of a JSON file."
Write-Output ''
Write-Output "Next: ./2-Invoke-RagQuery.ps1 -Question 'How long can a SecureLink Guest profile last?'"
