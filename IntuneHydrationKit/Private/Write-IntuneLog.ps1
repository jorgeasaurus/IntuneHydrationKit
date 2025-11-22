function Write-IntuneLog {
    <#
    .SYNOPSIS
        Writes a log message to console and file
    
    .DESCRIPTION
        Internal logging function for the IntuneHydrationKit module
    
    .PARAMETER Message
        The message to log
    
    .PARAMETER Level
        The log level (INFO, WARNING, ERROR, SUCCESS)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Create log directory if it doesn't exist
    if (-not (Test-Path $Script:LogPath)) {
        New-Item -Path $Script:LogPath -ItemType Directory -Force | Out-Null
    }
    
    # Write to log file
    if ($Script:LogFile) {
        Add-Content -Path $Script:LogFile -Value $logMessage
    }
    
    # Write to console with color
    switch ($Level) {
        "INFO"    { Write-Host $logMessage -ForegroundColor Cyan }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        "ERROR"   { Write-Host $logMessage -ForegroundColor Red }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
    }
}
