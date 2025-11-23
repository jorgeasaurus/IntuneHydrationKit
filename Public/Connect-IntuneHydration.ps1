function Connect-IntuneHydration {
    <#
    .SYNOPSIS
        Connects to Microsoft Graph with required scopes for Intune hydration
    .DESCRIPTION
        Establishes authentication to Microsoft Graph using interactive or certificate-based auth.
        Supports multiple cloud environments: Global (Commercial), USGov, USGovDoD, Germany, China.
    .PARAMETER TenantId
        The Azure AD tenant ID
    .PARAMETER ClientId
        Application (client) ID for certificate-based auth
    .PARAMETER CertificateThumbprint
        Certificate thumbprint for authentication
    .PARAMETER Interactive
        Use interactive authentication
    .PARAMETER Environment
        Graph environment: Global, USGov, USGovDoD, Germany, China
    .EXAMPLE
        Connect-IntuneHydration -TenantId "contoso.onmicrosoft.com" -Interactive
    .EXAMPLE
        Connect-IntuneHydration -TenantId "contoso.onmicrosoft.us" -Interactive -Environment USGov
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$TenantId,

        [Parameter(Mandatory = $true, ParameterSetName = 'Certificate')]
        [ValidateNotNullOrEmpty()]
        [string]$ClientId,

        [Parameter(Mandatory = $true, ParameterSetName = 'Certificate')]
        [ValidatePattern('^[A-Fa-f0-9]{40}$')]
        [string]$CertificateThumbprint,

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
        "Group.ReadWrite.All",
        "Policy.ReadWrite.ConditionalAccess",
        "Directory.ReadWrite.All"
    )

    # Store environment for use by other functions
    $script:GraphEnvironment = $Environment
    $script:GraphEndpoint = switch ($Environment) {
        'Global'    { 'https://graph.microsoft.com' }
        'USGov'     { 'https://graph.microsoft.us' }
        'USGovDoD'  { 'https://dod-graph.microsoft.us' }
        'Germany'   { 'https://graph.microsoft.de' }
        'China'     { 'https://microsoftgraph.chinacloudapi.cn' }
    }

    Write-Information "Connecting to $Environment environment ($script:GraphEndpoint)" -InformationAction Continue

    try {
        $connectParams = @{
            TenantId = $TenantId
            Environment = $Environment
            ErrorAction = 'Stop'
        }

        if ($Interactive) {
            $connectParams['Scopes'] = $scopes
        }
        else {
            $connectParams['ClientId'] = $ClientId
            $connectParams['CertificateThumbprint'] = $CertificateThumbprint
        }

        Connect-MgGraph @connectParams

        $script:HydrationState.Connected = $true
        $script:HydrationState.TenantId = $TenantId
        $script:HydrationState.Environment = $Environment

        Write-Information "Successfully connected to tenant: $TenantId ($Environment)" -InformationAction Continue
    }
    catch {
        Write-Error "Failed to connect to Microsoft Graph: $_"
        throw
    }
}
