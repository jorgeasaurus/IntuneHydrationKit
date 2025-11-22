<#
.SYNOPSIS
    Module for managing tenant-specific endpoint configurations.

.DESCRIPTION
    Provides functions to retrieve and manage Microsoft Graph API endpoints
    for different tenant types including Commercial, GCC, GCC High, and DoD.
#>

function Get-TenantEndpointConfiguration {
    <#
    .SYNOPSIS
        Gets the Microsoft Graph and Azure AD endpoint URLs for a specific tenant type.
    
    .PARAMETER TenantType
        The type of Microsoft 365 tenant.
    
    .OUTPUTS
        Hashtable containing endpoint URLs and configuration.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('Commercial', 'GCC', 'GCCHigh', 'DoD')]
        [string]$TenantType
    )
    
    $EndpointConfigurations = @{
        'Commercial' = @{
            GraphEndpoint = 'https://graph.microsoft.com'
            LoginEndpoint = 'https://login.microsoftonline.com'
            Environment = 'Global'
            Description = 'Microsoft 365 Commercial Cloud'
            RequiresUSPerson = $false
            ComplianceLevel = 'Commercial'
        }
        'GCC' = @{
            GraphEndpoint = 'https://graph.microsoft.com'
            LoginEndpoint = 'https://login.microsoftonline.com'
            Environment = 'USGov'
            Description = 'Microsoft 365 Government Community Cloud (GCC)'
            RequiresUSPerson = $false
            ComplianceLevel = 'FedRAMP Moderate'
        }
        'GCCHigh' = @{
            GraphEndpoint = 'https://graph.microsoft.us'
            LoginEndpoint = 'https://login.microsoftonline.us'
            Environment = 'USGovDoD'
            Description = 'Microsoft 365 Government Community Cloud High (GCC High)'
            RequiresUSPerson = $true
            ComplianceLevel = 'FedRAMP High'
        }
        'DoD' = @{
            GraphEndpoint = 'https://dod-graph.microsoft.us'
            LoginEndpoint = 'https://login.microsoftonline.us'
            Environment = 'USGovDoD'
            Description = 'Microsoft 365 Department of Defense (DoD)'
            RequiresUSPerson = $true
            ComplianceLevel = 'DoD IL5'
        }
    }
    
    $Config = $EndpointConfigurations[$TenantType]
    
    if (-not $Config) {
        Write-Error "Invalid tenant type: $TenantType"
        return $null
    }
    
    return $Config
}

function Test-TenantAccess {
    <#
    .SYNOPSIS
        Validates access to a tenant and checks permissions.
    
    .PARAMETER TenantId
        The Azure AD Tenant ID.
    
    .PARAMETER TenantType
        The type of Microsoft 365 tenant.
    
    .OUTPUTS
        Hashtable with Success status and Message.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$TenantId,
        
        [Parameter(Mandatory=$true)]
        [ValidateSet('Commercial', 'GCC', 'GCCHigh', 'DoD')]
        [string]$TenantType
    )
    
    try {
        # Verify connection to Microsoft Graph
        $Context = Get-MgContext
        
        if (-not $Context) {
            return @{
                Success = $false
                Message = "Not connected to Microsoft Graph"
            }
        }
        
        # Verify tenant ID matches
        if ($Context.TenantId -ne $TenantId) {
            return @{
                Success = $false
                Message = "Connected to different tenant. Expected: $TenantId, Connected: $($Context.TenantId)"
            }
        }
        
        # Check required permissions for Intune management
        $RequiredScopes = @(
            'DeviceManagementConfiguration.ReadWrite.All',
            'DeviceManagementManagedDevices.ReadWrite.All',
            'Group.ReadWrite.All'
        )
        
        $MissingScopes = @()
        foreach ($Scope in $RequiredScopes) {
            if ($Context.Scopes -notcontains $Scope) {
                $MissingScopes += $Scope
            }
        }
        
        if ($MissingScopes.Count -gt 0) {
            return @{
                Success = $false
                Message = "Missing required permissions: $($MissingScopes -join ', ')"
            }
        }
        
        # Validate tenant type matches endpoint
        $EndpointConfig = Get-TenantEndpointConfiguration -TenantType $TenantType
        if ($Context.Environment -ne $EndpointConfig.Environment) {
            return @{
                Success = $false
                Message = "Tenant environment mismatch. Expected: $($EndpointConfig.Environment), Connected: $($Context.Environment)"
            }
        }
        
        return @{
            Success = $true
            Message = "Tenant access validated successfully"
        }
    }
    catch {
        return @{
            Success = $false
            Message = "Error validating tenant access: $($_.Exception.Message)"
        }
    }
}

function Connect-MgGraphForTenant {
    <#
    .SYNOPSIS
        Connects to Microsoft Graph with tenant-specific configuration.
    
    .PARAMETER TenantId
        The Azure AD Tenant ID.
    
    .PARAMETER TenantType
        The type of Microsoft 365 tenant.
    
    .PARAMETER EndpointConfig
        Endpoint configuration hashtable from Get-TenantEndpointConfiguration.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$TenantId,
        
        [Parameter(Mandatory=$true)]
        [ValidateSet('Commercial', 'GCC', 'GCCHigh', 'DoD')]
        [string]$TenantType,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$EndpointConfig
    )
    
    # Define required scopes
    $Scopes = @(
        'DeviceManagementConfiguration.ReadWrite.All',
        'DeviceManagementManagedDevices.ReadWrite.All',
        'DeviceManagementServiceConfig.ReadWrite.All',
        'Group.ReadWrite.All',
        'Directory.Read.All'
    )
    
    # Validate tenant type and set environment
    $Config = Get-TenantEndpointConfiguration -TenantType $TenantType
    
    if (-not $Config) {
        return @{
            Success = $false
            Message = "Invalid tenant type: $TenantType"
        }
    }
    
    # Connection parameters
    $ConnectParams = @{
        TenantId = $TenantId
        Scopes = $Scopes
        NoWelcome = $true
    }
    
    # Add environment-specific parameters
    if ($TenantType -in @('GCCHigh', 'DoD')) {
        $ConnectParams.Environment = $Config.Environment
    }
    
    # Connect to Microsoft Graph
    try {
        Connect-MgGraph @ConnectParams -ErrorAction Stop
    }
    catch {
        throw "Failed to connect to Microsoft Graph for $TenantType tenant: $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function Get-TenantEndpointConfiguration, Test-TenantAccess, Connect-MgGraphForTenant
