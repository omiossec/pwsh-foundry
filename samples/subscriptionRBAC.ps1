$subscriptionID = "00000000-0000-0000-0000-000000000000"

$roleAssignment = Get-AzRoleAssignment -Scope "/subscriptions/$($subscriptionID)"

$roleAssignmentJson = $roleAssignment | ConvertTo-Json -Depth 10


$systemPrompt = "You are an Azure identity and access security specialist. Given a list of RBAC role assignments (principal, role, scope), flag: Owner or Contributor assigned at subscription scope to users (not service principals), Guest users with any role above Reader, service principals with Owner at subscription scope, assignments missing expiry (eligible vs. permanent via PIM), and duplicate role assignments. Output as a risk-sorted list."
$userMessage = "Analyze the following Azure RBAC assignments and flag over-privilege issues: $($roleAssignmentJson)"

Import-Module ./src/PwshFoundry/PwshFoundry.psd1 -Force

$msg    = New-FoundryMessage -UserPrompt $userMessage -SystemPrompt $systemPrompt
$result = New-FoundryChat -Message $msg -Model 'phi-3-mini-128k-instruct-qnn-npu:3'

Write-Output "RBAC Analysis Result:`n$($result.message.content)"