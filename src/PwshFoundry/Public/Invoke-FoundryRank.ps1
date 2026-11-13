#Requires -Version 7.0

function Invoke-FoundryRank {
    <#
    .SYNOPSIS
        Ranks candidate answers by relevance with a local Foundry ranking model (clm-v0.1-8b).
    .DESCRIPTION
        POSTs a request to the Foundry Local /v1/rank endpoint (Foundry Local 0.14.0+). Ranking
        models do not generate text: they score each candidate answer against an optional question
        and an optional JSON context.

        Candidates can be given with -Answer or piped in; all piped candidates are collected and
        ranked in a single request.

        The model does not need to be loaded, only downloaded: the service starts its runtime on demand.
    .PARAMETER Model
        Alias ('clm-v0.1-8b') or variant id ('clm-v0.1-8b-generic-gpu:1') of a ranking model.
    .PARAMETER Answer
        Candidate answers to rank. Accepts pipeline input.
    .PARAMETER Question
        Optional question or prompt the candidates answer.
    .PARAMETER Context
        Optional context: any object that converts to JSON (hashtable, PSCustomObject, array, string).
    .PARAMETER Temperature
        Request temperature, greater than 0 and at most 100. The service default is 1.0.
    .PARAMETER Catalog
        'Public' (default) for Microsoft catalog models, 'Local' for models registered in the
        Local Catalog (BYOM).
    .PARAMETER Raw
        Return the raw service response instead of the PwshFoundry.Ranking object.
    .EXAMPLE
        Invoke-FoundryRank -Model 'clm-v0.1-8b' -Question 'Which language automates Windows administration?' `
            -Answer 'PowerShell', 'COBOL', 'Excel macros'
    .EXAMPLE
        Get-Content ./faq-answers.txt |
            Invoke-FoundryRank -Model 'clm-v0.1-8b' -Question 'How do I reset my password?' -Context @{ product = 'VPN' }
    .NOTES
        Requires Foundry Local 0.14.0 or later. Foundry Local 0.14.0 tags clm models with the task
        'ranking' while /v1/rank expects 'text-ranking', so the service rejects them with HTTP 400
        until this is fixed upstream.
    #>
    [CmdletBinding()]
    [OutputType('PwshFoundry.Ranking')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Model,

        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string[]] $Answer,

        [Parameter()]
        [string] $Question,

        [Parameter()]
        [object] $Context,

        [Parameter()]
        [ValidateScript({ $_ -gt 0 -and $_ -le 100 }, ErrorMessage = 'Temperature must be greater than 0 and at most 100.')]
        [double] $Temperature,

        [Parameter()]
        [ValidateSet('Public', 'Local')]
        [string] $Catalog = 'Public',

        [Parameter()]
        [switch] $Raw
    )

    begin {
        # The Local (BYOM) catalog is not part of the CLI model list, so only public models are checked here.
        if ($Catalog -eq 'Public') {
            $catalogMatches = @(Resolve-FoundryModel -Name $Model)
            if ($catalogMatches.Count -eq 0) {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.ArgumentException]::new(
                            "Model '$Model' does not exist in the Foundry catalog. Use Get-FoundryModelList to get a valid model id."
                        ),
                        'FoundryModelNotFound',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                        $Model
                    )
                )
            }
            if (-not ($catalogMatches | Where-Object { $_.cached })) {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.InvalidOperationException]::new(
                            "Model '$Model' is not downloaded. Download it first with Save-FoundryModel -ModelID '$Model'."
                        ),
                        'FoundryModelNotCached',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                        $Model
                    )
                )
            }
        }

        $allAnswers = [System.Collections.Generic.List[string]]::new()
    }

    process {
        foreach ($item in $Answer) {
            $allAnswers.Add($item)
        }
    }

    end {
        $body = [ordered]@{
            model   = $Model
            answers = @($allAnswers)
        }
        if ($PSBoundParameters.ContainsKey('Question')) {
            $body['question'] = $Question
        }
        if ($PSBoundParameters.ContainsKey('Context')) {
            $body['context'] = $Context
        }
        if ($PSBoundParameters.ContainsKey('Temperature')) {
            $body['temperature'] = $Temperature
        }

        Write-Verbose "Ranking $($allAnswers.Count) candidate(s) with model '$Model'."

        try {
            $response = Invoke-FoundryApiRequest -Action 'rank' -Method POST -Body $body -Catalog $Catalog `
                -ErrorAction Stop
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }

        if ($Raw) {
            return $response
        }

        [PSCustomObject]@{
            PSTypeName = 'PwshFoundry.Ranking'
            Model      = $response.model
            Question   = $body['question']
            Answers    = @($allAnswers)
            Result     = $response
        }
    }
}
