function Get-HydrationAuthParameters {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$AuthenticationSettings,

        [Parameter(Mandatory)]
        [string]$TenantId
    )

    $authParameters = @{
        TenantId = $TenantId
    }

    if ($AuthenticationSettings.environment) {
        $authParameters['Environment'] = $AuthenticationSettings.environment
    }

    if ($AuthenticationSettings.mode -eq 'clientSecret') {
        $authParameters['ClientId'] = $AuthenticationSettings.clientId
        if ($AuthenticationSettings.clientSecret -is [SecureString]) {
            $authParameters['ClientSecret'] = $AuthenticationSettings.clientSecret
        } else {
            $convertToSecureStringParams = @{
                AsPlainText = $true
                Force       = $true
            }
            $authParameters['ClientSecret'] = $AuthenticationSettings.clientSecret | ConvertTo-SecureString @convertToSecureStringParams
        }
    } else {
        $authParameters['Interactive'] = $true
    }

    return $authParameters
}
