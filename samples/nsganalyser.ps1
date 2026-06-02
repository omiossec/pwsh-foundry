

$systemPrompt = "You are a cloud security engineer specializing in Azure network security groups. Analyze NSG rule exports and flag: inbound rules allowing Any source (0.0.0.0/0), rules on sensitive ports (22, 3389, 1433, 5432) without source restriction, rules with Allow overriding a higher-priority Deny, and unused or redundant rules. Output as a risk list sorted by severity."

$nsg = Get-AzNetworkSecurityGroup -Name default-nsg -ResourceGroupName 01-lab-depstack

$rules = $nsg.SecurityRules | ForEach-Object {
    [PSCustomObject]@{
        Name                     = $_.Name
        Priority                 = $_.Priority
        Access                   = $_.Access
        Direction                = $_.Direction
        SourceAddressPrefix     = $_.SourceAddressPrefix
        DestinationPortRange    = $_.DestinationPortRange
        Protocol                = $_.Protocol
    }
}

$userMessage = "Analyze the following NSG rules and identify potential security risks: `n" + ($rules | ConvertTo-Json -Depth 5)


Import-Module ./src/PwshFoundry/PwshFoundry.psd1 -Force

$msg    = New-FoundryMessage -UserPrompt $userMessage -SystemPrompt $systemPrompt
$result = New-FoundryChat -Message $msg -Model 'phi-3-mini-128k-instruct-qnn-npu:3'

Write-Output "AI Analysis Result:`n$($result.message.content)"