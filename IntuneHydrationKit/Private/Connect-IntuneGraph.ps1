function Connect-IntuneGraph {
    <#
    .SYNOPSIS
        Connects to Microsoft Graph with required scopes for Intune management
    
    .DESCRIPTION
        Establishes connection to Microsoft Graph with all necessary permissions for Intune hydration
    
    .PARAMETER TenantId
        Azure AD Tenant ID (optional, will prompt if not provided)
    
    .OUTPUTS
        Boolean indicating successful connection
    
    .EXAMPLE
        Connect-IntuneGraph
        
    .EXAMPLE
        Connect-IntuneGraph -TenantId "your-tenant-id"
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory=$false)]
        [string]$TenantId
    )
    
    Write-IntuneLog "Connecting to Microsoft Graph..." -Level INFO
    
    $scopes = @(
        "DeviceManagementConfiguration.ReadWrite.All",
        "DeviceManagementManagedDevices.ReadWrite.All",
        "DeviceManagementServiceConfig.ReadWrite.All",
        "Group.ReadWrite.All",
        "Policy.ReadWrite.ConditionalAccess",
        "Directory.Read.All"
    )
    
    try {
        if ($TenantId) {
            Connect-MgGraph -TenantId $TenantId -Scopes $scopes -ErrorAction Stop
        }
        else {
            Connect-MgGraph -Scopes $scopes -ErrorAction Stop
        }
        
        $context = Get-MgContext
        Write-IntuneLog "Successfully connected to Microsoft Graph" -Level SUCCESS
        Write-IntuneLog "Tenant: $($context.TenantId)" -Level INFO
        Write-IntuneLog "Account: $($context.Account)" -Level INFO
        return $true
    }
    catch {
        Write-IntuneLog "Failed to connect to Microsoft Graph: $_" -Level ERROR
        return $false
    }
}
