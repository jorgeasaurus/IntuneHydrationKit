function Connect-IntuneHydration {
    <#
    .SYNOPSIS
        Connects to Microsoft Graph with required scopes for Intune hydration
    .DESCRIPTION
        Establishes authentication to Microsoft Graph using interactive or client secret auth.
        Supports multiple cloud environments: Global (Commercial), USGov, USGovDoD, Germany, China.
    .PARAMETER TenantId
        The Azure AD tenant ID (GUID format). Optional for interactive authentication; required for client secret authentication.
    .PARAMETER ClientId
        Application (client) ID for app registration auth
    .PARAMETER ClientSecret
        Client secret for authentication (use SecureString for production)
    .PARAMETER Interactive
        Use interactive authentication
    .PARAMETER Environment
        Graph environment: Global, USGov, USGovDoD, Germany, China
    .PARAMETER Scopes
        Delegated Microsoft Graph scopes to request for interactive authentication.
        Defaults to the full Intune Hydration Kit scope set when omitted.
    .PARAMETER ForceConsent
        Request the Microsoft identity consent prompt during interactive authentication.
    .EXAMPLE
        Connect-IntuneHydration -Interactive -Environment USGov
    .EXAMPLE
        Connect-IntuneHydration -TenantId "00000000-0000-0000-0000-000000000000" -Interactive
    .EXAMPLE
        Connect-IntuneHydration -TenantId "00000000-0000-0000-0000-000000000000" -ClientId "app-id" -ClientSecret $secret
    .EXAMPLE
        Connect-IntuneHydration -TenantId "00000000-0000-0000-0000-000000000000" -Interactive -Environment USGov
    #>
    [CmdletBinding(DefaultParameterSetName = 'Interactive')]
    param(
        [Parameter(ParameterSetName = 'Interactive')]
        [Parameter(Mandatory = $true, ParameterSetName = 'ClientSecret')]
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
        [string]$Environment = 'Global',

        [Parameter(ParameterSetName = 'Interactive')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Scopes,

        [Parameter(ParameterSetName = 'Interactive')]
        [switch]$ForceConsent
    )

    $resolvedScopes = if ($Scopes) { $Scopes } else { Get-HydrationGraphScopes }
    $environmentInfo = Get-HydrationGraphEnvironmentInfo -Environment $Environment
    $isInteractiveAuth = $PSCmdlet.ParameterSetName -eq 'Interactive' -or $Interactive.IsPresent
    Write-Information (Format-HydrationDisplayMessage -Message "Connecting to $Environment environment ($($environmentInfo.Endpoint))" -Style 'Info' -Emoji '🔐') -InformationAction Continue

    try {
        $connectParams = @{
            Environment = $Environment
            NoWelcome   = $true
            ErrorAction = 'Stop'
        }
        if ($TenantId) {
            $connectParams['TenantId'] = $TenantId
        }

        if ($isInteractiveAuth) {
            $browserTenantId = if ($TenantId) { $TenantId } else { 'organizations' }
            $browserConnection = Connect-HydrationGraphViaBrowser -TenantId $browserTenantId -Scopes $resolvedScopes -Environment $Environment -ForceConsent:$ForceConsent
            $connectedTenantId = $browserConnection.TenantId

            if ($connectedTenantId -notmatch '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') {
                throw 'Unable to determine the signed-in tenant ID after interactive authentication.'
            }
        } else {
            # Create credential object for client secret auth
            $credential = New-Object System.Management.Automation.PSCredential($ClientId, $ClientSecret)
            $connectParams['ClientSecretCredential'] = $credential
            Connect-MgGraph @connectParams
            $connectedTenantId = $TenantId
        }

        $null = Set-HydrationConnectionState -TenantId $connectedTenantId -Environment $Environment

        Write-Information (Format-HydrationDisplayMessage -Message "Successfully connected to tenant: $(Get-ObfuscatedTenantId -TenantId $connectedTenantId) ($Environment)" -Style 'Success' -Emoji '✅') -InformationAction Continue
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
