#Requires -Version 7.4

$script:FoundryCliBin = $null

$script:FoundryVersionCache     = $null
$script:FoundryVersionCacheTime = $null

$script:FoundryWebServerProcess  = $null
$script:FoundryWebServerEndpoint = $null
$script:FoundryWebServerModelId  = $null
$script:FoundryWebServerTempDir  = $null

$script:FoundryModelListSdkExe     = $null
$script:FoundryModelListSdkTempDir = $null

foreach ($folder in @('Classes', 'Private', 'Public')) {
    Get-ChildItem -Path "$PSScriptRoot\$folder\*.ps1" -ErrorAction SilentlyContinue |
        ForEach-Object { . $_.FullName }
}
