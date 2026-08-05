#Requires -Version 7.0

<#
    Helper functions for the RAG sample. These are intentionally kept in the sample
    rather than in the PwshFoundry module: they are the teaching material, and the
    point is to be able to read exactly what chunking and retrieval do.

    Requires PwshFoundry to be imported first (Compare-FoundryEmbedding is used by
    Get-RelevantChunk).
#>

function ConvertTo-DocumentChunk {
    <#
    .SYNOPSIS
        Splits a document into overlapping chunks of roughly MaxWords words.
    .DESCRIPTION
        Embedding models turn a passage into a single vector, so a whole document
        embedded as one unit produces a vector that is an average of everything it
        discusses and matches nothing well. Splitting into chunks keeps each vector
        about one topic.

        Chunks are packed at paragraph boundaries so a chunk rarely starts mid-sentence.
        Consecutive chunks share OverlapWords words: without overlap, a fact that
        straddles a boundary ("...approval is required above" | "500 EUR...") is lost
        from both chunks.
    .PARAMETER Text
        Full text of the document.
    .PARAMETER Source
        Name used to identify where a chunk came from (typically the file name).
    .PARAMETER MaxWords
        Target maximum words per chunk. Paragraphs longer than this are windowed.
    .PARAMETER OverlapWords
        Number of words carried from the end of one chunk into the start of the next.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [string] $Text,

        [Parameter(Mandatory)]
        [string] $Source,

        [Parameter()]
        [ValidateRange(20, 1000)]
        [int] $MaxWords = 120,

        [Parameter()]
        [ValidateRange(0, 200)]
        [int] $OverlapWords = 25
    )

    $title = if ($Text -match '(?m)^#\s+(.+)$') { $Matches[1].Trim() } else { $Source }

    # Strip markdown markup before chunking. The markers are noise twice over:
    # they perturb the embedding, and they make the text the model finally reads
    # harder to quote from ("a maximum of **30 days**"). Heading *text* is kept,
    # because it is useful context about what a chunk is discussing.
    $plainText = $Text -replace '(?m)^#{1,6}\s*', '' -replace '\*\*', '' -replace '`', ''

    $paragraphs = @(
        $plainText -split '\r?\n\s*\r?\n' |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ }
    )

    # Paragraphs longer than the whole budget are pre-split, so that the packing
    # loop below never has to deal with a segment it cannot fit.
    $segments = [System.Collections.Generic.List[string[]]]::new()
    foreach ($paragraph in $paragraphs) {
        $words = @($paragraph -split '\s+' | Where-Object { $_ })

        if ($words.Count -le $MaxWords) {
            $segments.Add([string[]] $words)
            continue
        }

        for ($start = 0; $start -lt $words.Count; $start += $MaxWords) {
            $end = [math]::Min($start + $MaxWords - 1, $words.Count - 1)
            $segments.Add([string[]] $words[$start..$end])
        }
    }

    # Greedily pack segments into chunks, seeding each new chunk with the tail of
    # the previous one so context is not severed at the boundary.
    $chunkWordLists = [System.Collections.Generic.List[string[]]]::new()
    $current = [System.Collections.Generic.List[string]]::new()

    foreach ($segment in $segments) {
        if ($current.Count -gt 0 -and ($current.Count + $segment.Count) -gt $MaxWords) {
            $chunkWordLists.Add($current.ToArray())

            $tail = if ($OverlapWords -gt 0 -and $current.Count -gt $OverlapWords) {
                $current.GetRange($current.Count - $OverlapWords, $OverlapWords).ToArray()
            }
            else {
                [string[]] @()
            }

            $current = [System.Collections.Generic.List[string]]::new()
            if ($tail.Count -gt 0) {
                # Cast is required: PowerShell re-wraps the if-expression result as Object[].
                $current.AddRange([string[]] $tail)
            }
        }

        $current.AddRange([string[]] $segment)
    }

    if ($current.Count -gt 0) {
        $chunkWordLists.Add($current.ToArray())
    }

    for ($i = 0; $i -lt $chunkWordLists.Count; $i++) {
        [PSCustomObject]@{
            Id        = '{0}#{1}' -f $Source, $i
            Source    = $Source
            Title     = $title
            Text      = $chunkWordLists[$i] -join ' '
            WordCount = $chunkWordLists[$i].Count
        }
    }
}

function Get-RelevantChunk {
    <#
    .SYNOPSIS
        Ranks indexed chunks by cosine similarity to a query embedding.
    .DESCRIPTION
        This is the "retrieval" in retrieval-augmented generation. Every chunk is
        scored against the question and the best few are returned.

        The scan is linear - every chunk is compared on every query. That is the
        right choice for a demo corpus and the wrong choice past a few thousand
        chunks, where a real system uses an approximate nearest-neighbour index.

        No score threshold is applied here on purpose: the caller sees the top
        scores and decides whether anything was relevant enough to use.
    .PARAMETER QueryEmbedding
        Embedding of the question (an object from New-FoundryEmbedding, or a vector).
    .PARAMETER Chunk
        Indexed chunks, each carrying an Embedding property.
    .PARAMETER TopN
        How many of the highest-scoring chunks to return.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [object] $QueryEmbedding,

        [Parameter(Mandatory)]
        [object[]] $Chunk,

        [Parameter()]
        [ValidateRange(1, 50)]
        [int] $TopN = 3
    )

    $scored = foreach ($candidate in $Chunk) {
        [PSCustomObject]@{
            Score = Compare-FoundryEmbedding -ReferenceEmbedding $QueryEmbedding `
                                             -DifferenceEmbedding $candidate.Embedding
            Chunk = $candidate
        }
    }

    $ranked = @($scored | Sort-Object -Property Score -Descending | Select-Object -First $TopN)

    for ($i = 0; $i -lt $ranked.Count; $i++) {
        [PSCustomObject]@{
            Rank  = $i + 1
            Score = $ranked[$i].Score
            Chunk = $ranked[$i].Chunk
        }
    }
}

function Build-GroundedPrompt {
    <#
    .SYNOPSIS
        Builds the system and user prompt that ground the model in retrieved context.
    .DESCRIPTION
        This is the "augmented" step, and it is where RAG is won or lost. The
        retrieved chunks are pasted into the prompt as numbered blocks, and the
        system prompt tells the model to use only those blocks, to cite them, and
        to admit when they do not contain the answer.

        Without that instruction the model happily blends retrieved context with
        half-remembered pretraining and the citations become meaningless.
    .PARAMETER Question
        The user's question.
    .PARAMETER Context
        Ranked results from Get-RelevantChunk.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [string] $Question,

        [Parameter(Mandatory)]
        [object[]] $Context
    )

    # The order of these instructions matters. An early, prominent "refuse if you
    # cannot find it" makes small models refuse questions the context does answer,
    # so the instruction to answer comes first and the refusal is the last resort.
    $systemPrompt = @'
You are a Contoso internal documentation assistant. Answer the user's question
using the numbered context blocks supplied in their message.

- Read every context block before answering; the answer is usually a specific
  figure, limit, or rule stated in one of them.
- Quote that figure or rule exactly as written, and cite the block it came from,
  like [1].
- Use only what the context blocks say. Never add outside knowledge, and never
  invent a number, a name, or a date that does not appear in them.
- Answer in one or two sentences.
- Only if none of the blocks contains the answer, reply exactly:
  "The provided documents do not answer that question."
'@

    $blocks = foreach ($item in $Context) {
        "[{0}] (source: {1})`n{2}" -f $item.Rank, $item.Chunk.Source, $item.Chunk.Text
    }

    $userPrompt = @"
Context blocks:

$($blocks -join "`n`n")

Question: $Question
"@

    [PSCustomObject]@{
        SystemPrompt = $systemPrompt
        UserPrompt   = $userPrompt
    }
}

Export-ModuleMember -Function ConvertTo-DocumentChunk, Get-RelevantChunk, Build-GroundedPrompt
