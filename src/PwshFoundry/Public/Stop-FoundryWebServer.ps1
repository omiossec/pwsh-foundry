#Requires -Version 7.4

function Stop-FoundryWebServer {
    <#
    .SYNOPSIS
        Stops the Foundry web server started by Start-FoundryWebServer.
    .DESCRIPTION
        Terminates the background .NET host process (and its entire process tree),
        removes the temporary build directory, and clears the module-level server state.
    .EXAMPLE
        Stop-FoundryWebServer
    #>
    [CmdletBinding()]
    param()

    if (-not $script:FoundryWebServerProcess) {
        Write-Warning 'No Foundry web server is currently tracked by this module session. Nothing to stop.'
        return
    }

    if ($script:FoundryWebServerProcess.HasExited) {
        Write-Verbose "Foundry web server process (PID $($script:FoundryWebServerProcess.Id)) had already exited."
    }
    else {
        Write-Verbose "Stopping Foundry web server (PID $($script:FoundryWebServerProcess.Id), endpoint: $script:FoundryWebServerEndpoint)..."
        try {
            $script:FoundryWebServerProcess.Kill($true)
            $null = $script:FoundryWebServerProcess.WaitForExit(5000)
        }
        catch {
            Write-Warning "Error while terminating Foundry web server process: $($_.Exception.Message)"
        }
    }

    if ($script:FoundryWebServerTempDir -and (Test-Path $script:FoundryWebServerTempDir)) {
        Write-Verbose "Removing temporary build directory '$script:FoundryWebServerTempDir'..."
        Remove-Item -Recurse -Force $script:FoundryWebServerTempDir -ErrorAction SilentlyContinue
    }

    $script:FoundryWebServerProcess  = $null
    $script:FoundryWebServerEndpoint = $null
    $script:FoundryWebServerModelId  = $null
    $script:FoundryWebServerTempDir  = $null
}
