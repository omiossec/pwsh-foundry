<#
    Demonstrates function calling (tools) with New-FoundryChat: the model can ask
    PowerShell to run a real command and use its result to answer the question.

    Note: small local models often don't emit structured tool calls unless the tool
    is forced via -ToolChoice, so this sample forces the first call and lets the
    model answer freely afterwards.
#>

param(
    [Parameter()]
    [string] $Model = 'Phi-4-mini-instruct-generic-gpu'
)

Import-Module ./src/PwshFoundry/PwshFoundry.psd1 -Force

$currentTimeTool = New-FoundryTool -Name 'Get-CurrentTime' `
    -Description 'Returns the current local date and time.' `
    -Handler { (Get-Date).ToString('o') }

$diskSpaceTool = New-FoundryTool -Name 'Get-FreeDiskSpace' `
    -Description 'Returns the free disk space, in gigabytes, for a given drive letter.' `
    -Parameters @{
        DriveLetter = @{ type = 'string'; description = "Drive letter, e.g. 'C'" }
    } `
    -Required 'DriveLetter' `
    -Handler {
        param($DriveLetter)
        $drive = Get-PSDrive -Name $DriveLetter.TrimEnd(':') -ErrorAction Stop
        [math]::Round($drive.Free / 1GB, 2)
    }

$tools = @($currentTimeTool, $diskSpaceTool)

$context = New-FoundryChatContext -UserPrompt 'What time is it right now?'

$result = New-FoundryChat -Context $context -Model $Model -Tools $tools -ToolChoice 'Get-CurrentTime'

Write-Output "Assistant: $($result.message.content)"

$context.AddUserPrompt('How much free space is left on drive C?')

$result = New-FoundryChat -Context $context -Model $Model -Tools $tools -ToolChoice 'Get-FreeDiskSpace'

Write-Output "Assistant: $($result.message.content)"
