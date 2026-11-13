#Requires -Version 7.0

function Invoke-FoundryDecision {
    <#
    .SYNOPSIS
        Asks questions about a JSON state to a local Foundry decision model (kev-4b, kev-0.8b).
    .DESCRIPTION
        POSTs a request to the Foundry Local /v1/systemone endpoint (Foundry Local 0.14.0+).
        Decision models do not generate text: they answer typed questions about a state object.

        Three question types are supported, as in 'foundry decide':
          - Predicate (noul): a yes/no question; the model returns the probability that it is true.
          - Choice: pick one of several labelled options.
          - Score: place the state on an ordered scale.

        Questions are sent in the order they are given (Predicate, then Choice, then Score, then
        Question). Use ordered dictionaries ([ordered]@{}) to control the order within a parameter.

        The model does not need to be loaded, only downloaded: the service starts its runtime on demand.
    .PARAMETER Model
        Alias ('kev-0.8b') or variant id ('kev-0.8b-generic-gpu:1') of a decision model.
    .PARAMETER State
        The data the questions are about. Any object that converts to JSON (hashtable, PSCustomObject,
        array, string).
    .PARAMETER Predicate
        Predicate questions: question id -> instructions, e.g. @{ billing = 'Is this about billing?' }.
    .PARAMETER Choice
        Choice questions: question id -> dictionary of option key -> label,
        e.g. @{ team = [ordered]@{ sales = 'Sales'; support = 'Support' } }.
    .PARAMETER Score
        Score questions: question id -> ordered list of levels (lowest first),
        e.g. @{ priority = 'low', 'medium', 'high' }.
    .PARAMETER Question
        Raw question definitions sent as-is: question id -> @{ type; instructions; criteria }.
        Use it for question options not covered by the other parameters.
    .PARAMETER Temperature
        Request temperature. Decision models currently require exactly 1.0 (the service default),
        so leave it unset unless the model documents otherwise.
    .PARAMETER Catalog
        'Public' (default) for Microsoft catalog models, 'Local' for models registered in the
        Local Catalog (BYOM).
    .PARAMETER Raw
        Return the raw service response instead of the PwshFoundry.Decision object.
    .EXAMPLE
        $ticket = @{ subject = 'Charged twice'; body = 'My invoice is wrong, I was charged twice' }
        Invoke-FoundryDecision -Model 'kev-0.8b' -State $ticket `
            -Predicate @{ billing = 'Is this ticket about billing?' } `
            -Choice @{ team = [ordered]@{ sales = 'Sales'; support = 'Support' } } `
            -Score @{ priority = 'low', 'medium', 'high' }
    .NOTES
        Requires Foundry Local 0.14.0 or later. Foundry Local 0.14.0 tags kev models with the task
        'decision' while /v1/systemone expects 'typed-decision', so the service rejects them with
        HTTP 400 until this is fixed upstream.
    #>
    [CmdletBinding()]
    [OutputType('PwshFoundry.Decision')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Model,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object] $State,

        [Parameter()]
        [System.Collections.IDictionary] $Predicate,

        [Parameter()]
        [System.Collections.IDictionary] $Choice,

        [Parameter()]
        [System.Collections.IDictionary] $Score,

        [Parameter()]
        [System.Collections.IDictionary] $Question,

        [Parameter()]
        [ValidateRange(0.0, 100.0)]
        [double] $Temperature,

        [Parameter()]
        [ValidateSet('Public', 'Local')]
        [string] $Catalog = 'Public',

        [Parameter()]
        [switch] $Raw
    )

    $questions = [ordered]@{}

    $addQuestion = {
        param([string] $id, [System.Collections.IDictionary] $definition)
        if ([string]::IsNullOrWhiteSpace($id)) {
            throw [System.ArgumentException]::new('Question ids must not be empty.')
        }
        if ($questions.Contains($id)) {
            throw [System.ArgumentException]::new("Question id '$id' is used more than once.")
        }
        $questions[$id] = $definition
    }

    try {
        foreach ($key in $Predicate.Keys) {
            $instructions = "$($Predicate[$key])"
            if ([string]::IsNullOrWhiteSpace($instructions)) {
                throw [System.ArgumentException]::new("Predicate '$key' needs non-empty instructions.")
            }
            & $addQuestion $key ([ordered]@{ type = 'noul'; instructions = $instructions })
        }

        foreach ($key in $Choice.Keys) {
            $options = $Choice[$key]
            if ($options -isnot [System.Collections.IDictionary] -or $options.Count -lt 2) {
                throw [System.ArgumentException]::new(
                    "Choice '$key' must be a dictionary of at least two option key -> label pairs."
                )
            }
            & $addQuestion $key ([ordered]@{ type = 'choice'; criteria = $options })
        }

        foreach ($key in $Score.Keys) {
            $levels = @($Score[$key] | ForEach-Object { "$_" } | Where-Object { $_ })
            if ($levels.Count -lt 2) {
                throw [System.ArgumentException]::new("Score '$key' must list at least two levels.")
            }
            & $addQuestion $key ([ordered]@{ type = 'score'; criteria = $levels })
        }

        foreach ($key in $Question.Keys) {
            $definition = $Question[$key]
            if ($definition -isnot [System.Collections.IDictionary] -or -not $definition['type']) {
                throw [System.ArgumentException]::new("Question '$key' must be a dictionary with a 'type' entry.")
            }
            & $addQuestion $key $definition
        }
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'FoundryInvalidDecisionQuestion',
                [System.Management.Automation.ErrorCategory]::InvalidArgument,
                $null
            )
        )
    }

    if ($questions.Count -eq 0) {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.ArgumentException]::new('Specify at least one -Predicate, -Choice, -Score or -Question.'),
                'FoundryDecisionNoQuestion',
                [System.Management.Automation.ErrorCategory]::InvalidArgument,
                $null
            )
        )
    }

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

    $body = [ordered]@{
        model     = $Model
        state     = $State
        questions = $questions
    }
    if ($PSBoundParameters.ContainsKey('Temperature')) {
        $body['temperature'] = $Temperature
    }

    Write-Verbose "Asking $($questions.Count) question(s) to decision model '$Model'."

    try {
        $response = Invoke-FoundryApiRequest -Action 'decision' -Method POST -Body $body -Catalog $Catalog `
            -ErrorAction Stop
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }

    if ($Raw) {
        return $response
    }

    [PSCustomObject]@{
        PSTypeName = 'PwshFoundry.Decision'
        Model      = $response.model
        Answers    = $response.answers
        Questions  = $questions
        State      = $State
        Usage      = $response.usage
    }
}
