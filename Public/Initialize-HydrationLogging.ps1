function Initialize-HydrationLogging {
    <#
    .SYNOPSIS
        Initializes logging for the hydration session
    .PARAMETER LogPath
        Path to write log files. Defaults to OS temp directory under IntuneHydrationKit/Logs
    .PARAMETER EnableVerbose
        Enable verbose logging
    .EXAMPLE
        Initialize-HydrationLogging
        # Uses default temp path: $env:TEMP/IntuneHydrationKit/Logs (Windows) or /tmp/IntuneHydrationKit/Logs (macOS/Linux)
    .EXAMPLE
        Initialize-HydrationLogging -LogPath "./MyLogs"
        # Uses custom path
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$LogPath,

        [Parameter()]
        [switch]$EnableVerbose
    )

    # Set default log path to OS-appropriate temp directory if not specified
    if (-not $LogPath) {
        $tempBase = [System.IO.Path]::GetTempPath()
        $LogPath = Join-Path -Path $tempBase -ChildPath 'IntuneHydrationKit/Logs'
    }

    if (-not (Test-Path -Path $LogPath)) {
        New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
    }

    $script:LogPath = $LogPath
    $script:VerboseLogging = $EnableVerbose

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $script:CurrentLogFile = Join-Path -Path $LogPath -ChildPath "hydration-$timestamp.log"

    # Clear existing log file
    if (Test-Path -Path $script:CurrentLogFile) {
        Clear-Content -Path $script:CurrentLogFile
    }

    Write-HydrationLog -Message "Logging initialized at: $($script:CurrentLogFile)" -Level Info
}
