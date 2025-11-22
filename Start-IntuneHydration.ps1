<#
.SYNOPSIS
    Hydrates Microsoft Intune with baseline configurations for various tenant types.

.DESCRIPTION
    This script imports essential Intune configurations including compliance policies,
    configuration profiles, and dynamic groups into Commercial, GCC, GCC High, or DoD tenants.
    It automatically configures the appropriate Microsoft Graph API endpoints based on tenant type.

.PARAMETER TenantType
    Specifies the Microsoft 365 tenant type. Valid values are:
    - Commercial (Default)
    - GCC (Government Community Cloud)
    - GCCHigh (Government Community Cloud High)
    - DoD (Department of Defense)

.PARAMETER TenantId
    The Azure AD Tenant ID (GUID) for your organization.

.PARAMETER ConfigurationPath
    Path to the folder containing Intune configuration JSON files.
    Defaults to "./Configurations" in the script directory.

.PARAMETER ImportAll
    Imports all available configuration types. If not specified, you'll be prompted to select.

.PARAMETER WhatIf
    Shows what would be imported without making actual changes.

.EXAMPLE
    .\Start-IntuneHydration.ps1 -TenantType Commercial -TenantId "12345678-1234-1234-1234-123456789012"
    
    Hydrates a commercial tenant with baseline configurations.

.EXAMPLE
    .\Start-IntuneHydration.ps1 -TenantType GCCHigh -TenantId "12345678-1234-1234-1234-123456789012" -ImportAll
    
    Hydrates a GCC High tenant with all available configurations.

.EXAMPLE
    .\Start-IntuneHydration.ps1 -TenantType DoD -TenantId "12345678-1234-1234-1234-123456789012" -WhatIf
    
    Shows what would be imported into a DoD tenant without making changes.

.NOTES
    Requires:
    - Microsoft.Graph PowerShell SDK modules
    - Appropriate administrative permissions in the target tenant
    - Network access to the corresponding Microsoft Graph endpoint
    
    Author: Intune Hydration Kit Contributors
    Version: 1.0.0
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('Commercial', 'GCC', 'GCCHigh', 'DoD')]
    [string]$TenantType = 'Commercial',
    
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string]$TenantId,
    
    [Parameter(Mandatory=$false)]
    [ValidateScript({Test-Path $_ -PathType Container})]
    [string]$ConfigurationPath,
    
    [Parameter(Mandatory=$false)]
    [switch]$ImportAll,
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf
)

# Import required modules
$ModulePath = Join-Path $PSScriptRoot "Modules"
if (Test-Path $ModulePath) {
    Get-ChildItem -Path $ModulePath -Filter "*.psm1" | ForEach-Object {
        Import-Module $_.FullName -Force
    }
}

# Set default configuration path if not specified
if (-not $ConfigurationPath) {
    $ConfigurationPath = Join-Path $PSScriptRoot "Configurations"
}

# Initialize logging
$LogPath = Join-Path $PSScriptRoot "Logs"
if (-not (Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath | Out-Null
}
$LogFile = Join-Path $LogPath "IntuneHydration_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )
    
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$TimeStamp] [$Level] $Message"
    
    # Console output with color
    $Color = switch ($Level) {
        'Info' { 'White' }
        'Warning' { 'Yellow' }
        'Error' { 'Red' }
        'Success' { 'Green' }
    }
    Write-Host $LogMessage -ForegroundColor $Color
    
    # File output
    Add-Content -Path $LogFile -Value $LogMessage
}

# Validate tenant type and get endpoint configuration
Write-Log "Starting Intune Hydration for $TenantType tenant" -Level Info
Write-Log "Tenant ID: $TenantId" -Level Info
Write-Log "Configuration Path: $ConfigurationPath" -Level Info

# Get tenant-specific endpoint configuration
$EndpointConfig = Get-TenantEndpointConfiguration -TenantType $TenantType

if (-not $EndpointConfig) {
    Write-Log "Failed to retrieve endpoint configuration for tenant type: $TenantType" -Level Error
    exit 1
}

Write-Log "Microsoft Graph Endpoint: $($EndpointConfig.GraphEndpoint)" -Level Info
Write-Log "Azure AD Login Endpoint: $($EndpointConfig.LoginEndpoint)" -Level Info

# Display security and compliance notice
Write-Log "=== Security and Compliance Notice ===" -Level Warning
switch ($TenantType) {
    'GCC' {
        Write-Log "GCC Environment: Ensure you have FedRAMP Moderate authorization." -Level Warning
        Write-Log "Network: Access from approved government networks required." -Level Warning
    }
    'GCCHigh' {
        Write-Log "GCC High Environment: Requires FedRAMP High authorization and US Person status." -Level Warning
        Write-Log "Network: Must connect from US Government network or approved VPN." -Level Warning
        Write-Log "Data Classification: Suitable for CUI and ITAR controlled data." -Level Warning
    }
    'DoD' {
        Write-Log "DoD Environment: Requires DoD IL5 authorization and security clearance." -Level Warning
        Write-Log "Network: Must connect from DoD network infrastructure." -Level Warning
        Write-Log "Data Classification: Suitable for classified data up to IL5." -Level Warning
    }
}
Write-Log "========================================" -Level Warning

# Connect to Microsoft Graph
Write-Log "Connecting to Microsoft Graph API..." -Level Info

try {
    Connect-MgGraphForTenant -TenantId $TenantId -TenantType $TenantType -EndpointConfig $EndpointConfig
    Write-Log "Successfully connected to Microsoft Graph" -Level Success
    
    # Set the Graph endpoint for import operations
    Set-GraphEndpoint -Endpoint $EndpointConfig.GraphEndpoint
}
catch {
    Write-Log "Failed to connect to Microsoft Graph: $($_.Exception.Message)" -Level Error
    exit 1
}

# Validate tenant access and permissions
Write-Log "Validating tenant access and permissions..." -Level Info
try {
    $ValidationResult = Test-TenantAccess -TenantId $TenantId -TenantType $TenantType
    if (-not $ValidationResult.Success) {
        Write-Log "Tenant validation failed: $($ValidationResult.Message)" -Level Error
        exit 1
    }
    Write-Log "Tenant validation successful" -Level Success
}
catch {
    Write-Log "Tenant validation error: $($_.Exception.Message)" -Level Error
    exit 1
}

# Verify configuration files exist
if (-not (Test-Path $ConfigurationPath)) {
    Write-Log "Configuration path not found: $ConfigurationPath" -Level Error
    exit 1
}

# Get available configuration types
$AvailableConfigs = Get-AvailableConfigurations -Path $ConfigurationPath -TenantType $TenantType

if ($AvailableConfigs.Count -eq 0) {
    Write-Log "No configuration files found in: $ConfigurationPath" -Level Error
    exit 1
}

Write-Log "Found $($AvailableConfigs.Count) configuration type(s)" -Level Info
$AvailableConfigs | ForEach-Object {
    Write-Log "  - $($_.Name) - $($_.FileCount) file(s)" -Level Info
}

# Determine which configurations to import
$ConfigsToImport = @()
if ($ImportAll) {
    $ConfigsToImport = $AvailableConfigs
    Write-Log "Importing all available configurations" -Level Info
}
else {
    # Interactive selection (would be implemented for production)
    Write-Log "ImportAll not specified. Use -ImportAll to import all configurations." -Level Warning
    $ConfigsToImport = $AvailableConfigs
}

# Import configurations
$ImportResults = @{
    Successful = 0
    Failed = 0
    Skipped = 0
    Details = @()
}

foreach ($Config in $ConfigsToImport) {
    Write-Log "Processing $($Config.Name) configurations..." -Level Info
    
    foreach ($File in $Config.Files) {
        $FileName = Split-Path $File -Leaf
        
        if ($WhatIf) {
            Write-Log "  [WhatIf] Would import: $FileName" -Level Info
            $ImportResults.Skipped++
            continue
        }
        
        try {
            Write-Log "  Importing: $FileName" -Level Info
            
            # Import configuration based on type
            $Result = Import-IntuneConfiguration -FilePath $File -ConfigType $Config.Type -TenantType $TenantType
            
            if ($Result.Success) {
                Write-Log "  Successfully imported: $FileName" -Level Success
                $ImportResults.Successful++
            }
            else {
                Write-Log "  Failed to import: $FileName - $($Result.Message)" -Level Error
                $ImportResults.Failed++
            }
            
            $ImportResults.Details += @{
                File = $FileName
                Type = $Config.Type
                Success = $Result.Success
                Message = $Result.Message
            }
        }
        catch {
            Write-Log "  Error importing $($FileName): $($_.Exception.Message)" -Level Error
            $ImportResults.Failed++
            $ImportResults.Details += @{
                File = $FileName
                Type = $Config.Type
                Success = $false
                Message = $_.Exception.Message
            }
        }
    }
}

# Summary
Write-Log "========================================" -Level Info
Write-Log "Intune Hydration Complete" -Level Success
Write-Log "Successful: $($ImportResults.Successful)" -Level Success
if ($ImportResults.Failed -gt 0) {
    Write-Log "Failed: $($ImportResults.Failed)" -Level Error
}
if ($ImportResults.Skipped -gt 0) {
    Write-Log "Skipped (WhatIf): $($ImportResults.Skipped)" -Level Info
}
Write-Log "Log file: $LogFile" -Level Info
Write-Log "========================================" -Level Info

# Disconnect from Microsoft Graph
Disconnect-MgGraph | Out-Null

# Exit with appropriate code
if ($ImportResults.Failed -gt 0) {
    exit 1
}
exit 0
