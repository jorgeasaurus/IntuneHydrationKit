function Connect-IntuneHydration {
    <#
    .SYNOPSIS
        Connects to Microsoft Graph with required scopes for Intune hydration
    .DESCRIPTION
        Establishes authentication to Microsoft Graph using interactive or client secret auth.
        Supports multiple cloud environments: Global (Commercial), USGov, USGovDoD, Germany, China.
    .PARAMETER TenantId
        The Azure AD tenant ID (GUID format)
    .PARAMETER ClientId
        Application (client) ID for app registration auth
    .PARAMETER ClientSecret
        Client secret for authentication (use SecureString for production)
    .PARAMETER Interactive
        Use interactive authentication
    .PARAMETER Environment
        Graph environment: Global, USGov, USGovDoD, Germany, China
    .EXAMPLE
        Connect-IntuneHydration -TenantId "00000000-0000-0000-0000-000000000000" -Interactive
    .EXAMPLE
        Connect-IntuneHydration -TenantId "00000000-0000-0000-0000-000000000000" -ClientId "app-id" -ClientSecret $secret
    .EXAMPLE
        Connect-IntuneHydration -TenantId "00000000-0000-0000-0000-000000000000" -Interactive -Environment USGov
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
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

    $scopes = Get-HydrationGraphScopes
    $environmentInfo = Get-HydrationGraphEnvironmentInfo -Environment $Environment
    Write-Information (Format-HydrationDisplayMessage -Message "Connecting to $Environment environment ($($environmentInfo.Endpoint))" -Style 'Info' -Emoji '🔐') -InformationAction Continue

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

        $null = Set-HydrationConnectionState -TenantId $TenantId -Environment $Environment

        Write-Information (Format-HydrationDisplayMessage -Message "Successfully connected to tenant: $(Get-ObfuscatedTenantId -TenantId $TenantId) ($Environment)" -Style 'Success' -Emoji '✅') -InformationAction Continue
    } catch {
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("Failed to connect to Microsoft Graph: $($_.Exception.Message)", $_.Exception),
            'GraphConnectionFailed',
            [System.Management.Automation.ErrorCategory]::ConnectionError,
            $TenantId
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }
}

