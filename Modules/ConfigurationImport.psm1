<#
.SYNOPSIS
    Module for importing Intune configurations.

.DESCRIPTION
    Provides functions to import various Intune configuration types including
    compliance policies, configuration profiles, and dynamic groups.
#>

# Module-scoped variable to store the Graph endpoint
$script:GraphEndpoint = $null

function Set-GraphEndpoint {
    <#
    .SYNOPSIS
        Sets the Graph endpoint to use for API calls.
    
    .PARAMETER Endpoint
        The Graph API endpoint URL.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Endpoint
    )
    
    $script:GraphEndpoint = $Endpoint
}

function Get-GraphEndpoint {
    <#
    .SYNOPSIS
        Gets the current Graph endpoint.
    
    .OUTPUTS
        The Graph API endpoint URL or default.
    #>
    [CmdletBinding()]
    param()
    
    if ($script:GraphEndpoint) {
        return $script:GraphEndpoint
    }
    
    # Try to get from context
    $Context = Get-MgContext
    if ($Context) {
        # Map environment names to endpoints
        switch ($Context.Environment) {
            'Global' { return 'https://graph.microsoft.com' }
            'USGov' { return 'https://graph.microsoft.com' }
            'USGovDoD' { return 'https://graph.microsoft.us' }
            'China' { return 'https://microsoftgraph.chinacloudapi.cn' }
            'Germany' { return 'https://graph.microsoft.de' }
            default { return 'https://graph.microsoft.com' }
        }
    }
    
    # Default to commercial endpoint
    return 'https://graph.microsoft.com'
}

function Get-AvailableConfigurations {
    <#
    .SYNOPSIS
        Gets available configuration files from the specified path.
    
    .PARAMETER Path
        Path to the configurations directory.
    
    .PARAMETER TenantType
        The type of Microsoft 365 tenant.
    
    .OUTPUTS
        Array of configuration type objects.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,
        
        [Parameter(Mandatory=$true)]
        [ValidateSet('Commercial', 'GCC', 'GCCHigh', 'DoD')]
        [string]$TenantType
    )
    
    $ConfigTypes = @(
        @{
            Name = 'Compliance Policies'
            Type = 'CompliancePolicy'
            Folder = 'CompliancePolicies'
        },
        @{
            Name = 'Configuration Profiles'
            Type = 'ConfigurationProfile'
            Folder = 'ConfigurationProfiles'
        },
        @{
            Name = 'Device Configurations'
            Type = 'DeviceConfiguration'
            Folder = 'DeviceConfigurations'
        },
        @{
            Name = 'Dynamic Groups'
            Type = 'DynamicGroup'
            Folder = 'DynamicGroups'
        },
        @{
            Name = 'Security Baselines'
            Type = 'SecurityBaseline'
            Folder = 'SecurityBaselines'
        }
    )
    
    $AvailableConfigs = @()
    
    foreach ($ConfigType in $ConfigTypes) {
        $ConfigPath = Join-Path $Path $ConfigType.Folder
        
        # Check for tenant-specific configurations first
        $TenantSpecificPath = Join-Path $ConfigPath $TenantType
        $SearchPath = if (Test-Path $TenantSpecificPath) { $TenantSpecificPath } else { $ConfigPath }
        
        if (Test-Path $SearchPath) {
            $Files = Get-ChildItem -Path $SearchPath -Filter "*.json" -File -ErrorAction SilentlyContinue
            
            if ($Files.Count -gt 0) {
                $AvailableConfigs += @{
                    Name = $ConfigType.Name
                    Type = $ConfigType.Type
                    Folder = $ConfigType.Folder
                    Files = $Files.FullName
                    FileCount = $Files.Count
                }
            }
        }
    }
    
    return $AvailableConfigs
}

function Import-IntuneConfiguration {
    <#
    .SYNOPSIS
        Imports an Intune configuration from a JSON file.
    
    .PARAMETER FilePath
        Path to the configuration JSON file.
    
    .PARAMETER ConfigType
        The type of configuration being imported.
    
    .PARAMETER TenantType
        The type of Microsoft 365 tenant.
    
    .OUTPUTS
        Hashtable with Success status and Message.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath,
        
        [Parameter(Mandatory=$true)]
        [string]$ConfigType,
        
        [Parameter(Mandatory=$true)]
        [ValidateSet('Commercial', 'GCC', 'GCCHigh', 'DoD')]
        [string]$TenantType
    )
    
    try {
        # Read configuration file
        $ConfigContent = Get-Content -Path $FilePath -Raw | ConvertFrom-Json
        
        # Validate configuration
        if (-not $ConfigContent) {
            return @{
                Success = $false
                Message = "Configuration file is empty or invalid"
            }
        }
        
        # Import based on configuration type
        $Result = switch ($ConfigType) {
            'CompliancePolicy' { Import-CompliancePolicy -Config $ConfigContent -TenantType $TenantType }
            'ConfigurationProfile' { Import-ConfigurationProfile -Config $ConfigContent -TenantType $TenantType }
            'DeviceConfiguration' { Import-DeviceConfiguration -Config $ConfigContent -TenantType $TenantType }
            'DynamicGroup' { Import-DynamicGroup -Config $ConfigContent -TenantType $TenantType }
            'SecurityBaseline' { Import-SecurityBaseline -Config $ConfigContent -TenantType $TenantType }
            default {
                return @{
                    Success = $false
                    Message = "Unknown configuration type: $ConfigType"
                }
            }
        }
        
        return $Result
    }
    catch {
        return @{
            Success = $false
            Message = "Error importing configuration: $($_.Exception.Message)"
        }
    }
}

function Import-CompliancePolicy {
    <#
    .SYNOPSIS
        Imports a compliance policy configuration.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$Config,
        
        [Parameter(Mandatory=$true)]
        [string]$TenantType
    )
    
    try {
        # Remove properties that shouldn't be included in creation
        $Config.PSObject.Properties.Remove('id')
        $Config.PSObject.Properties.Remove('createdDateTime')
        $Config.PSObject.Properties.Remove('lastModifiedDateTime')
        
        # Get the Graph endpoint
        $GraphEndpoint = Get-GraphEndpoint
        
        # Create compliance policy using Microsoft Graph
        $Uri = "$GraphEndpoint/beta/deviceManagement/deviceCompliancePolicies"
        $Policy = Invoke-MgGraphRequest -Method POST -Uri $Uri -Body ($Config | ConvertTo-Json -Depth 10)
        
        return @{
            Success = $true
            Message = "Created compliance policy: $($Config.displayName)"
            PolicyId = $Policy.id
        }
    }
    catch {
        return @{
            Success = $false
            Message = "Failed to create compliance policy: $($_.Exception.Message)"
        }
    }
}

function Import-ConfigurationProfile {
    <#
    .SYNOPSIS
        Imports a configuration profile.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$Config,
        
        [Parameter(Mandatory=$true)]
        [string]$TenantType
    )
    
    try {
        # Remove properties that shouldn't be included in creation
        $Config.PSObject.Properties.Remove('id')
        $Config.PSObject.Properties.Remove('createdDateTime')
        $Config.PSObject.Properties.Remove('lastModifiedDateTime')
        
        # Get the Graph endpoint
        $GraphEndpoint = Get-GraphEndpoint
        
        # Create configuration profile using Microsoft Graph
        $Uri = "$GraphEndpoint/beta/deviceManagement/deviceConfigurations"
        $Profile = Invoke-MgGraphRequest -Method POST -Uri $Uri -Body ($Config | ConvertTo-Json -Depth 10)
        
        return @{
            Success = $true
            Message = "Created configuration profile: $($Config.displayName)"
            ProfileId = $Profile.id
        }
    }
    catch {
        return @{
            Success = $false
            Message = "Failed to create configuration profile: $($_.Exception.Message)"
        }
    }
}

function Import-DeviceConfiguration {
    <#
    .SYNOPSIS
        Imports a device configuration.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$Config,
        
        [Parameter(Mandatory=$true)]
        [string]$TenantType
    )
    
    try {
        # Remove properties that shouldn't be included in creation
        $Config.PSObject.Properties.Remove('id')
        $Config.PSObject.Properties.Remove('createdDateTime')
        $Config.PSObject.Properties.Remove('lastModifiedDateTime')
        
        # Get the Graph endpoint
        $GraphEndpoint = Get-GraphEndpoint
        
        # Create device configuration using Microsoft Graph
        $Uri = "$GraphEndpoint/beta/deviceManagement/deviceConfigurations"
        $DeviceConfig = Invoke-MgGraphRequest -Method POST -Uri $Uri -Body ($Config | ConvertTo-Json -Depth 10)
        
        return @{
            Success = $true
            Message = "Created device configuration: $($Config.displayName)"
            ConfigId = $DeviceConfig.id
        }
    }
    catch {
        return @{
            Success = $false
            Message = "Failed to create device configuration: $($_.Exception.Message)"
        }
    }
}

function Import-DynamicGroup {
    <#
    .SYNOPSIS
        Imports a dynamic Azure AD group.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$Config,
        
        [Parameter(Mandatory=$true)]
        [string]$TenantType
    )
    
    try {
        # Remove properties that shouldn't be included in creation
        $Config.PSObject.Properties.Remove('id')
        $Config.PSObject.Properties.Remove('createdDateTime')
        
        # Create dynamic group using Microsoft Graph
        $Group = New-MgGroup -DisplayName $Config.displayName `
                             -Description $Config.description `
                             -MailEnabled:$false `
                             -MailNickname $Config.mailNickname `
                             -SecurityEnabled:$true `
                             -GroupTypes @("DynamicMembership") `
                             -MembershipRule $Config.membershipRule `
                             -MembershipRuleProcessingState "On"
        
        return @{
            Success = $true
            Message = "Created dynamic group: $($Config.displayName)"
            GroupId = $Group.Id
        }
    }
    catch {
        return @{
            Success = $false
            Message = "Failed to create dynamic group: $($_.Exception.Message)"
        }
    }
}

function Import-SecurityBaseline {
    <#
    .SYNOPSIS
        Imports a security baseline configuration.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$Config,
        
        [Parameter(Mandatory=$true)]
        [string]$TenantType
    )
    
    try {
        # Remove properties that shouldn't be included in creation
        $Config.PSObject.Properties.Remove('id')
        $Config.PSObject.Properties.Remove('createdDateTime')
        $Config.PSObject.Properties.Remove('lastModifiedDateTime')
        
        # Get the Graph endpoint
        $GraphEndpoint = Get-GraphEndpoint
        
        # Create security baseline using Microsoft Graph
        $Uri = "$GraphEndpoint/beta/deviceManagement/intents"
        $Baseline = Invoke-MgGraphRequest -Method POST -Uri $Uri -Body ($Config | ConvertTo-Json -Depth 10)
        
        return @{
            Success = $true
            Message = "Created security baseline: $($Config.displayName)"
            BaselineId = $Baseline.id
        }
    }
    catch {
        return @{
            Success = $false
            Message = "Failed to create security baseline: $($_.Exception.Message)"
        }
    }
}

Export-ModuleMember -Function Get-AvailableConfigurations, Import-IntuneConfiguration, Set-GraphEndpoint
