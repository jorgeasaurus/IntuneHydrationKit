function Initialize-HydrationLogging {
    <#
    .SYNOPSIS
        Initializes logging for the hydration session
    .DESCRIPTION
        Sets up the logging infrastructure for a hydration run, creating the log directory
        and session log file. Configures both console and file logging with timestamps.
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
        [ValidateNotNullOrEmpty()]
        # Validation applies only if user explicitly provides a value; $null (omitted) uses default
        [string]$LogPath,

        [Parameter()]
        [switch]$EnableVerbose
    )

    # Set default log path to OS-appropriate temp directory if not specified
    if ([string]::IsNullOrWhiteSpace($LogPath)) {
        $LogPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 'IntuneHydrationKit/Logs'
    }

    # Create log directory if needed (New-Item -Force handles parent creation)
    $null = New-Item -Path $LogPath -ItemType Directory -Force -WhatIf:$false

    $script:LogPath = $LogPath
    $script:VerboseLogging = $EnableVerbose

    $script:HydrationSessionId = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:CurrentLogFile = Join-Path -Path $LogPath -ChildPath "hydration-$($script:HydrationSessionId).log"

    # Remove existing log file if present (ensures fresh start)
    Remove-Item -Path $script:CurrentLogFile -ErrorAction SilentlyContinue -Force

    Write-HydrationLog -Message "Logging initialized at: $($script:CurrentLogFile)" -Level Info
}
