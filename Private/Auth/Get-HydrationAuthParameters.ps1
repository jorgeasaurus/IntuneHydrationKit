function Get-HydrationAuthParameters {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$AuthenticationSettings,

        [Parameter()]
        [string]$TenantId
    )

    $authParams = @{}
    if ($TenantId) {
        $authParams['TenantId'] = $TenantId
    }

    if ($AuthenticationSettings.environment) {
        $authParams['Environment'] = $AuthenticationSettings.environment
    }

    if ($AuthenticationSettings.mode -eq 'clientSecret') {
        $authParams['ClientId'] = $AuthenticationSettings.clientId
        if ($AuthenticationSettings.clientSecret -is [SecureString]) {
            $authParams['ClientSecret'] = $AuthenticationSettings.clientSecret
        } else {
            $convertToSecureStringParams = @{
                AsPlainText = $true
                Force       = $true
            }
            $authParams['ClientSecret'] = $AuthenticationSettings.clientSecret | ConvertTo-SecureString @convertToSecureStringParams
        }
    } else {
        $authParams['Interactive'] = $true
    }

    return $authParams
}
