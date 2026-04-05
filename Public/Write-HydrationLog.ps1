function Write-HydrationLog {
    <#
    .SYNOPSIS
        Writes a log entry to the console and log file
    .DESCRIPTION
        Writes a timestamped, level-tagged log entry to both the console (with color-coded
        icons) and the current session log file. Used throughout the module to provide
        consistent diagnostic output during hydration operations.
    .PARAMETER Message
        The message to log
    .PARAMETER Level
        Log level (Info, Warning, Error, Debug)
    .PARAMETER Data
        Additional data to include
    .EXAMPLE
        Write-HydrationLog -Message "Importing compliance policies" -Level Info
    .EXAMPLE
        Write-HydrationLog -Message "Rate limited by Graph API" -Level Warning
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('Info', 'Warning', 'Error', 'Debug')]
        [string]$Level = 'Info',

        [Parameter()]
        [object]$Data
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"

    # Console output (friendly)
    $icons = @{
        'Info'    = '[i]'
        'Warning' = '[!]'
        'Error'   = '[x]'
        'Debug'   = '[~]'
    }
    $colors = @{
        'Info'    = 'Cyan'
        'Warning' = 'Yellow'
        'Error'   = 'Red'
        'Debug'   = 'Gray'
    }

    $consoleMessage = "$($icons[$Level]) $Message"

    if ($Level -eq 'Debug' -and -not $script:VerboseLogging) {
        # Suppress debug unless verbose enabled
        $consoleMessage = $null
    }

    if ($consoleMessage) {
        if ($Message -match '^Step \d+:') {
            Write-Host ""
            Write-Host "▶ $Message" -ForegroundColor $colors[$Level]
        } elseif ($Message -match '^===') {
            Write-Host ""
            Write-Host $Message -ForegroundColor $colors[$Level]
        } else {
            Write-Host "  $consoleMessage" -ForegroundColor $colors[$Level]
        }
    }

    # File output
    # Always write to log file regardless of -WhatIf (logging is observational, not a tenant change)
    if ($script:CurrentLogFile) {
        $logEntry | Out-File -FilePath $script:CurrentLogFile -Append -Encoding utf8 -WhatIf:$false
        if ($Data) {
            ($Data | ConvertTo-Json -Depth 5) | Out-File -FilePath $script:CurrentLogFile -Append -Encoding utf8 -WhatIf:$false
        }
    }
}
