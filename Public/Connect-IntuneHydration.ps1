function Connect-IntuneHydration {
    <#
    .SYNOPSIS
        Connects to Microsoft Graph with required scopes for Intune hydration
    .DESCRIPTION
        Establishes authentication to Microsoft Graph using interactive or client secret auth.
        Supports multiple cloud environments: Global (Commercial), USGov, USGovDoD, Germany, China.
    .PARAMETER TenantId
        The Azure AD tenant ID
    .PARAMETER ClientId
        Application (client) ID for app registration auth
    .PARAMETER ClientSecret
        Client secret for authentication (use SecureString for production)
    .PARAMETER Interactive
        Use interactive authentication
    .PARAMETER Environment
        Graph environment: Global, USGov, USGovDoD, Germany, China
    .EXAMPLE
        Connect-IntuneHydration -TenantId "contoso.onmicrosoft.com" -Interactive
    .EXAMPLE
        Connect-IntuneHydration -TenantId "contoso.onmicrosoft.com" -ClientId "app-id" -ClientSecret $secret
    .EXAMPLE
        Connect-IntuneHydration -TenantId "contoso.onmicrosoft.us" -Interactive -Environment USGov
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$TenantId,

        [Parameter(Mandatory = $true, ParameterSetName = 'ClientSecret')]
        [ValidateNotNullOrEmpty()]
        [string]$ClientId,

        [Parameter(Mandatory = $true, ParameterSetName = 'ClientSecret')]
        [ValidateNotNullOrEmpty()]
        [SecureString]$ClientSecret,

        [Parameter(ParameterSetName = 'Interactive')]
        [switch]$Interactive,

        [Parameter()]
        [ValidateSet('Global', 'USGov', 'USGovDoD', 'Germany', 'China')]
        [string]$Environment = 'Global'
    )

    $scopes = @(
        "DeviceManagementConfiguration.ReadWrite.All",
        "DeviceManagementServiceConfig.ReadWrite.All",
        "DeviceManagementManagedDevices.ReadWrite.All",
        "DeviceManagementScripts.ReadWrite.All",
        "DeviceManagementApps.ReadWrite.All",
        "Group.ReadWrite.All",
        "Policy.Read.All",
        "Policy.ReadWrite.ConditionalAccess",
        "Application.Read.All",
        "Directory.ReadWrite.All",
        "LicenseAssignment.Read.All",
        "Organization.Read.All"
    )

    # Store environment for use by other functions
    $script:GraphEnvironment = $Environment
    $script:GraphEndpoint = switch ($Environment) {
        'Global' { 'https://graph.microsoft.com' }
        'USGov' { 'https://graph.microsoft.us' }
        'USGovDoD' { 'https://dod-graph.microsoft.us' }
        'Germany' { 'https://graph.microsoft.de' }
        'China' { 'https://microsoftgraph.chinacloudapi.cn' }
    }

    Write-Host "Connecting to $Environment environment ($script:GraphEndpoint)"

    try {
        $connectParams = @{
            TenantId    = $TenantId
            Environment = $Environment
            NoWelcome   = $true
            ErrorAction = 'Stop'
        }

        if ($Interactive) {
            $connectParams['Scopes'] = $scopes
        } else {
            # Create credential object for client secret auth
            $credential = New-Object System.Management.Automation.PSCredential($ClientId, $ClientSecret)
            $connectParams['ClientSecretCredential'] = $credential
        }

        Connect-MgGraph @connectParams

        $script:HydrationState.Connected = $true
        $script:HydrationState.TenantId = $TenantId
        $script:HydrationState.Environment = $Environment

        Write-Host "Successfully connected to tenant: $(Get-ObfuscatedTenantId -TenantId $TenantId) ($Environment)"
    } catch {
        Write-Error "Failed to connect to Microsoft Graph: $_"
        throw
    }
}
