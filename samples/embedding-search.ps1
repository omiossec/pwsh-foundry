<#
    Semantic search over a small text corpus using a local Foundry embedding model
    (qwen3-embedding-0.6b or qwen3-embedding-8b). The corpus is embedded once with
    New-FoundryEmbedding; each query you type is embedded and ranked against the
    corpus with Compare-FoundryEmbedding (cosine similarity). Type 'exit' or 'quit'
    to end the session.
#>

param(
    [Parameter()]
    [string] $Model = 'qwen3-embedding-0.6b-generic-gpu',

    [Parameter()]
    [int] $TopN = 3
)

Import-Module ./src/PwshFoundry/PwshFoundry.psd1 -Force

$corpus = @(
    'Get-Process retrieves the processes running on the local computer.'
    'Azure Network Security Groups filter inbound and outbound traffic to Azure resources.'
    'Pester is the test framework for PowerShell, used for unit and integration testing.'
    'Azure Role-Based Access Control (RBAC) manages who has access to Azure resources.'
    'The pipeline passes objects from one PowerShell command to the next.'
    'Azure Kubernetes Service simplifies deploying managed Kubernetes clusters.'
    'PSScriptAnalyzer performs static analysis of PowerShell scripts and modules.'
    'Azure Storage accounts hold blobs, files, queues, and tables in the cloud.'
)

Write-Output "Embedding $($corpus.Count) corpus entries with '$Model' (first run loads the model)..."
$corpusEmbeddings = New-FoundryEmbedding -Model $Model -Text $corpus

while ($true) {
    $query = Read-Host "Search query (type 'exit' or 'quit' to end the session)"

    if ($query -in @('exit', 'quit')) {
        break
    }

    if ([string]::IsNullOrWhiteSpace($query)) {
        continue
    }

    $queryEmbedding = New-FoundryEmbedding -Model $Model -Text $query

    $ranked = $corpusEmbeddings | ForEach-Object {
        [PSCustomObject]@{
            Score = Compare-FoundryEmbedding -ReferenceEmbedding $queryEmbedding -DifferenceEmbedding $_
            Text  = $_.Text
        }
    } | Sort-Object -Property Score -Descending | Select-Object -First $TopN

    Write-Output ''
    foreach ($match in $ranked) {
        Write-Output ("{0:N4}  {1}" -f $match.Score, $match.Text)
    }
    Write-Output ''
}
