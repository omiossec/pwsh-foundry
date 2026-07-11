function New-FoundryLogEntries {
    <#
    .SYNOPSIS
        Appends a chat interaction entry to a Foundry log file.
    .DESCRIPTION
        Writes a single JSON-line entry containing a timestamp, the model name, and the
        system, user, and assistant prompts to a log file. Each call appends one entry;
        existing log content is preserved.
    .PARAMETER Model
        Name of the Foundry model used for the interaction.
    .PARAMETER SystemPrompt
        The system prompt sent to the model. Optional; defaults to an empty string.
    .PARAMETER UserPrompt
        The user prompt sent to the model.
    .PARAMETER AssistantPrompt
        The assistant's response returned by the model.
    .PARAMETER LogFilePath
        Path to the log file. Defaults to 'PwshFoundry_ChatLog.jsonl' in the current user's
        temporary directory.
    .EXAMPLE
        New-FoundryLogEntries -Model 'phi-3' -SystemPrompt 'You are helpful.' -UserPrompt 'Hi' -AssistantPrompt 'Hello!'

        Appends an entry to the default log file in the user's temp directory.
    .EXAMPLE
        New-FoundryLogEntries -Model 'phi-3' -SystemPrompt 'sys' -UserPrompt 'hi' -AssistantPrompt 'hello' -LogFilePath 'C:\logs\foundry.jsonl'

        Appends an entry to a specific log file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Model,

        [Parameter()]
        [string]$SystemPrompt = '',

        [Parameter(Mandatory)]
        [string]$UserPrompt,

        [Parameter(Mandatory)]
        [string]$AssistantPrompt,

        [Parameter()]
        [string]$LogFilePath = (Join-Path ([System.IO.Path]::GetTempPath()) 'PwshFoundry_ChatLog.jsonl')
    )

    $entry = [ordered]@{
        Timestamp       = (Get-Date).ToString('o')
        Model           = $Model
        SystemPrompt    = $SystemPrompt
        UserPrompt      = $UserPrompt
        AssistantPrompt = $AssistantPrompt
    }

    try {
        $entry | ConvertTo-Json -Compress | Add-Content -Path $LogFilePath -Encoding utf8
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new(
                    "Failed to write Foundry log entry to '$LogFilePath': $($_.Exception.Message)"
                ),
                'FoundryLogWriteError',
                [System.Management.Automation.ErrorCategory]::WriteError,
                $LogFilePath
            )
        )
    }
}
