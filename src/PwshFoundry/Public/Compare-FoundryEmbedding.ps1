#Requires -Version 7.0

function Compare-FoundryEmbedding {
    <#
    .SYNOPSIS
        Computes the cosine similarity between two embedding vectors.
    .DESCRIPTION
        Returns a value between -1 and 1 describing how similar two embedding vectors are:
        1 means identical direction, 0 means unrelated, -1 means opposite. Accepts either
        raw numeric vectors or the objects emitted by New-FoundryEmbedding (the Embedding
        property is unwrapped automatically). No API call is made; this is pure math.
    .PARAMETER ReferenceEmbedding
        The first embedding vector, or a New-FoundryEmbedding result object.
    .PARAMETER DifferenceEmbedding
        The second embedding vector, or a New-FoundryEmbedding result object.
    .EXAMPLE
        $a = New-FoundryEmbedding -Model 'qwen3-embedding-0.6b' -Text 'the cat sat on the mat'
        $b = New-FoundryEmbedding -Model 'qwen3-embedding-0.6b' -Text 'a feline rested on the rug'
        Compare-FoundryEmbedding -ReferenceEmbedding $a -DifferenceEmbedding $b
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory)]
        [object] $ReferenceEmbedding,

        [Parameter(Mandatory)]
        [object] $DifferenceEmbedding
    )

    [double[]] $reference = if ($ReferenceEmbedding.PSObject.Properties['Embedding']) {
        $ReferenceEmbedding.Embedding
    } else {
        $ReferenceEmbedding
    }

    [double[]] $difference = if ($DifferenceEmbedding.PSObject.Properties['Embedding']) {
        $DifferenceEmbedding.Embedding
    } else {
        $DifferenceEmbedding
    }

    if ($reference.Count -eq 0 -or $difference.Count -eq 0 -or $reference.Count -ne $difference.Count) {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.ArgumentException]::new(
                    "Embedding vectors must be non-empty and of equal length (got $($reference.Count) and $($difference.Count))."
                ),
                'FoundryEmbeddingLengthMismatch',
                [System.Management.Automation.ErrorCategory]::InvalidArgument,
                $DifferenceEmbedding
            )
        )
    }

    $dot   = 0.0
    $norm1 = 0.0
    $norm2 = 0.0

    for ($i = 0; $i -lt $reference.Count; $i++) {
        $dot   += $reference[$i] * $difference[$i]
        $norm1 += $reference[$i] * $reference[$i]
        $norm2 += $difference[$i] * $difference[$i]
    }

    if ($norm1 -eq 0.0 -or $norm2 -eq 0.0) {
        return [double] 0
    }

    return $dot / ([math]::Sqrt($norm1) * [math]::Sqrt($norm2))
}
