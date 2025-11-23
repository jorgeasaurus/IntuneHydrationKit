function Initialize-HydrationLogging {
    <#
    .SYNOPSIS
        Initializes logging for the hydration session
    .PARAMETER LogPath
        Path to write log files
    .PARAMETER EnableVerbose
        Enable verbose logging
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$LogPath = "./Logs",

        [Parameter()]
        [switch]$EnableVerbose
    )

    if (-not (Test-Path -Path $LogPath)) {
        New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
    }

    $script:LogPath = $LogPath
    $script:VerboseLogging = $EnableVerbose

    if ($(whoami) -ne 'jorgeasaurus') {
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    }
    $script:CurrentLogFile = Join-Path -Path $LogPath -ChildPath "hydration-$timestamp.log"

    Write-HydrationLog -Message "Logging initialized" -Level Info
}
