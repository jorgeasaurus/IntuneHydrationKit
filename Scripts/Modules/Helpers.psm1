#Requires -Version 7.0

<#
.SYNOPSIS
    Helper functions for IntuneHydrationKit
.DESCRIPTION
    Contains authentication, Graph wrapper with retry, logging, templating, and upsert helpers
#>

# Module-level state for logging
$script:LogPath = $null
$script:VerboseLogging = $false

#region Logging Functions

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

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $script:CurrentLogFile = Join-Path -Path $LogPath -ChildPath "hydration-$timestamp.log"

    Write-HydrationLog -Message "Logging initialized" -Level Info
}

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
        if ($Message -match '^Step \\d+:') {
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

#endregion

#region Graph API Helpers

function Invoke-GraphRequestWithRetry {
    <#
    .SYNOPSIS
        Invokes a Graph API request with retry logic
    .PARAMETER Method
        HTTP method
    .PARAMETER Uri
        Graph API URI
    .PARAMETER Body
        Request body
    .PARAMETER MaxRetries
        Maximum number of retries
    .PARAMETER RetryDelaySeconds
        Initial delay between retries (uses exponential backoff)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('GET', 'POST', 'PATCH', 'PUT', 'DELETE')]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter()]
        [object]$Body,

        [Parameter()]
        [int]$MaxRetries = 3,

        [Parameter()]
        [int]$RetryDelaySeconds = 2
    )

    $attempt = 0
    $lastError = $null

    while ($attempt -lt $MaxRetries) {
        $attempt++
        try {
            $params = @{
                Method = $Method
                Uri = $Uri
                ErrorAction = 'Stop'
            }

            if ($Body) {
                $params['Body'] = $Body | ConvertTo-Json -Depth 10
                $params['ContentType'] = 'application/json'
            }

            $response = Invoke-MgGraphRequest @params
            return $response
        }
        catch {
            $lastError = $_
            $statusCode = $_.Exception.Response.StatusCode.value__

            # Check for retryable errors (429, 503, 504)
            if ($statusCode -in @(429, 503, 504)) {
                $delay = $RetryDelaySeconds * [Math]::Pow(2, $attempt - 1)

                # Check for Retry-After header
                $retryAfter = $_.Exception.Response.Headers['Retry-After']
                if ($retryAfter) {
                    $delay = [int]$retryAfter
                }

                Write-HydrationLog -Message "Request failed with $statusCode. Retrying in $delay seconds (attempt $attempt of $MaxRetries)" -Level Warning
                Start-Sleep -Seconds $delay
            }
            else {
                # Non-retryable error
                throw
            }
        }
    }

    Write-HydrationLog -Message "Request failed after $MaxRetries attempts" -Level Error
    throw $lastError
}

#endregion

#region Template Helpers

function Get-TemplateFiles {
    <#
    .SYNOPSIS
        Gets all JSON template files from a directory
    .PARAMETER Path
        Path to the template directory
    .PARAMETER Recurse
        Search subdirectories
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ })]
        [string]$Path,

        [Parameter()]
        [switch]$Recurse
    )

    $params = @{
        Path = $Path
        Filter = "*.json"
        File = $true
    }

    if ($Recurse) {
        $params['Recurse'] = $true
    }

    Get-ChildItem @params
}

function Import-TemplateFile {
    <#
    .SYNOPSIS
        Imports and parses a JSON template file
    .PARAMETER Path
        Path to the template file
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ })]
        [string]$Path
    )

    try {
        $content = Get-Content -Path $Path -Raw -Encoding utf8
        $template = $content | ConvertFrom-Json -AsHashtable

        Write-HydrationLog -Message "Loaded template: $Path" -Level Debug
        return $template
    }
    catch {
        Write-HydrationLog -Message "Failed to load template: $Path - $_" -Level Error
        throw
    }
}

function Resolve-TemplateTokens {
    <#
    .SYNOPSIS
        Resolves placeholder tokens in a template
    .PARAMETER Template
        The template hashtable
    .PARAMETER Tokens
        Hashtable of token replacements
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Template,

        [Parameter(Mandatory = $true)]
        [hashtable]$Tokens
    )

    $json = $Template | ConvertTo-Json -Depth 20

    foreach ($key in $Tokens.Keys) {
        $placeholder = "{{$key}}"
        $json = $json -replace [regex]::Escape($placeholder), $Tokens[$key]
    }

    return $json | ConvertFrom-Json -AsHashtable
}

#endregion

#region Upsert Helpers

function Get-UpsertDecision {
    <#
    .SYNOPSIS
        Determines whether to create, update, or skip a resource
    .PARAMETER ExistingResource
        The existing resource (if any)
    .PARAMETER NewResource
        The new resource definition
    .PARAMETER ForceUpdate
        Force update even if no changes detected
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$ExistingResource,

        [Parameter(Mandatory = $true)]
        [object]$NewResource,

        [Parameter()]
        [switch]$ForceUpdate
    )

    if (-not $ExistingResource) {
        return @{
            Action = 'Create'
            Reason = 'Resource does not exist'
        }
    }

    if ($ForceUpdate) {
        return @{
            Action = 'Update'
            Reason = 'Force update requested'
            ExistingId = $ExistingResource.id
        }
    }

    # Compare resources (simplified - could be enhanced for deep comparison)
    $existingJson = $ExistingResource | ConvertTo-Json -Depth 10 -Compress
    $newJson = $NewResource | ConvertTo-Json -Depth 10 -Compress

    if ($existingJson -ne $newJson) {
        return @{
            Action = 'Update'
            Reason = 'Resource has changed'
            ExistingId = $ExistingResource.id
        }
    }

    return @{
        Action = 'Skip'
        Reason = 'Resource is up to date'
        ExistingId = $ExistingResource.id
    }
}

#endregion

#region Result Aggregation

function New-HydrationResult {
    <#
    .SYNOPSIS
        Creates a new hydration result object
    .PARAMETER Type
        Type of resource (Group, Policy, Baseline, etc.)
    .PARAMETER Name
        Resource name
    .PARAMETER Action
        Action taken (Created, Updated, Skipped, Failed)
    .PARAMETER Id
        Resource ID
    .PARAMETER Details
        Additional details
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Type,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Created', 'Updated', 'Skipped', 'Failed')]
        [string]$Action,

        [Parameter()]
        [string]$Id,

        [Parameter()]
        [string]$Details
    )

    return [PSCustomObject]@{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Type = $Type
        Name = $Name
        Action = $Action
        Id = $Id
        Details = $Details
    }
}

function Get-ResultSummary {
    <#
    .SYNOPSIS
        Summarizes a collection of hydration results
    .PARAMETER Results
        Array of hydration results
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowEmptyCollection()]
        [array]$Results = @()
    )

    $summary = @{
        Total = $Results.Count
        Created = ($Results | Where-Object { $_.Action -eq 'Created' }).Count
        Updated = ($Results | Where-Object { $_.Action -eq 'Updated' }).Count
        Skipped = ($Results | Where-Object { $_.Action -eq 'Skipped' }).Count
        Failed = ($Results | Where-Object { $_.Action -eq 'Failed' }).Count
        ByType = @{}
    }

    $Results | Group-Object -Property Type | ForEach-Object {
        $summary.ByType[$_.Name] = @{
            Total = $_.Count
            Created = ($_.Group | Where-Object { $_.Action -eq 'Created' }).Count
            Updated = ($_.Group | Where-Object { $_.Action -eq 'Updated' }).Count
            Skipped = ($_.Group | Where-Object { $_.Action -eq 'Skipped' }).Count
            Failed = ($_.Group | Where-Object { $_.Action -eq 'Failed' }).Count
        }
    }

    return $summary
}

#endregion

#region Settings Helpers

function Import-HydrationSettings {
    <#
    .SYNOPSIS
        Imports and validates hydration settings
    .PARAMETER Path
        Path to the settings file
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ })]
        [string]$Path
    )

    try {
        $content = Get-Content -Path $Path -Raw -Encoding utf8
        $settings = $content | ConvertFrom-Json -AsHashtable

        # Validate required fields
        if (-not $settings.tenant.tenantId) {
            throw "Missing required field: tenant.tenantId"
        }

        Write-HydrationLog -Message "Settings loaded from: $Path" -Level Info
        return $settings
    }
    catch {
        Write-HydrationLog -Message "Failed to load settings: $_" -Level Error
        throw
    }
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Initialize-HydrationLogging',
    'Write-HydrationLog',
    'Invoke-GraphRequestWithRetry',
    'Get-TemplateFiles',
    'Import-TemplateFile',
    'Resolve-TemplateTokens',
    'Get-UpsertDecision',
    'New-HydrationResult',
    'Get-ResultSummary',
    'Import-HydrationSettings'
)
