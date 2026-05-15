#Requires -Version 7.4

$script:FoundryCliBin = $null

foreach ($folder in @('Classes', 'Private', 'Public')) {
    Get-ChildItem -Path "$PSScriptRoot\$folder\*.ps1" -ErrorAction SilentlyContinue |
        ForEach-Object { . $_.FullName }
}
