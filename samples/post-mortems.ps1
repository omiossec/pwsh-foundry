# Get the content of the slack channel for post-mortem reports
$slackExportPath = 'C:\path\to\slack_export.json'
$slackData = Get-Content -Path $slackExportPath 

$systemPrompt = "You are an SRE and incident commander writing blameless post-mortems. Given raw incident notes and a timeline, produce a structured post-mortem with: incident summary, timeline (UTC), root cause, contributing factors, impact (users/services affected, duration), and follow-up action items with owners and priority. Be precise and blameless. Do not speculate beyond the provided notes."

$userMessage = "Write a post-mortem from the following raw incident notes: $($slackData)"

Import-Module ./src/PwshFoundry/PwshFoundry.psd1 -Force

$msg    = New-FoundryMessage -UserPrompt $userMessage -SystemPrompt $systemPrompt
$result = New-FoundryChat -Message $msg -Model 'phi-3-mini-128k-instruct-qnn-npu:3'

Write-Output "Post Mortem:`n$($result.message.content)"