function Write-HydrationLog {
    <#
    .SYNOPSIS
        Writes a log entry
    .PARAMETER Message
        The message to log
    .PARAMETER Level
        Log level (Info, Warning, Error, Debug)
    .PARAMETER Data
        Additional data to include
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
        }
        elseif ($Message -match '^===') {
            Write-Host ""
            Write-Host $Message -ForegroundColor $colors[$Level]
        }
        else {
            Write-Host "  $consoleMessage" -ForegroundColor $colors[$Level]
        }
    }

    # File output
    if ($script:CurrentLogFile) {
        $logEntry | Out-File -FilePath $script:CurrentLogFile -Append -Encoding utf8
        if ($Data) {
            ($Data | ConvertTo-Json -Depth 5) | Out-File -FilePath $script:CurrentLogFile -Append -Encoding utf8
        }
    }
}
