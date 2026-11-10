#Requires -Version 7.0

function New-FoundryEmbedding {
    <#
    .SYNOPSIS
        Creates embedding vectors for one or more texts using a local Foundry embedding model.
    .DESCRIPTION
        Builds an OpenAI-compatible embeddings request body and POSTs it to /v1/embeddings.
        Embedding models (e.g. qwen3-embedding-0.6b, qwen3-embedding-8b) turn text into
        numeric vectors; they do not support chat completions, so use this function instead
        of New-FoundryChat for those models.

        All texts are sent in a single batched request; pipeline input is accumulated and
        batched the same way. One object per input text is emitted, carrying the text, its
        index, and the embedding vector.
    .PARAMETER Text
        One or more texts to embed. Accepts pipeline input; piped strings are batched into
        a single API request.
    .PARAMETER Model
        Id of a local Foundry embedding model (e.g. 'qwen3-embedding-0.6b'). The model is
        loaded automatically if it is not already loaded.
    .EXAMPLE
        New-FoundryEmbedding -Model 'qwen3-embedding-0.6b' -Text 'PowerShell is a shell and scripting language'
    .EXAMPLE
        $vectors = 'first document', 'second document' | New-FoundryEmbedding -Model 'qwen3-embedding-0.6b'
        Compare-FoundryEmbedding -ReferenceEmbedding $vectors[0] -DifferenceEmbedding $vectors[1]
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string[]] $Text,

        [Parameter(Mandatory)]
        [string] $Model
    )

    begin {
        if (-not (Test-FoundryModelName -ModelName $Model)) {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.ArgumentException]::new(
                        "Model '$Model' does not exist in the local Foundry. Use Get-FoundryModelList or 'foundry model list' to get a valid model id."
                    ),
                    'FoundryModelNotFound',
                    [System.Management.Automation.ErrorCategory]::InvalidArgument,
                    $Model
                )
            )
        }

        $allText = [System.Collections.Generic.List[string]]::new()
    }

    process {
        foreach ($item in $Text) {
            $allText.Add($item)
        }
    }

    end {
        # The embeddings endpoint does not auto-load models and expects the versioned id of a loaded model.
        try {
            $resolvedModel = (Initialize-FoundryModel -Name $Model -ErrorAction Stop) ?? $Model

            $body = @{
                model = $resolvedModel
                input = @($allText)
            }

            Write-Verbose "Requesting embeddings for $($allText.Count) text(s) with model '$resolvedModel'."

            $response = Invoke-FoundryApiRequest -Action 'embeddings' -Method POST -Body $body -ErrorAction Stop
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }

        foreach ($entry in ($response.data | Sort-Object -Property index)) {
            [PSCustomObject]@{
                Index     = $entry.index
                Text      = $allText[$entry.index]
                Embedding = [double[]] $entry.embedding
                Model     = $response.model
                Usage     = $response.usage
            }
        }
    }
}
