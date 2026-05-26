function Connect-HydrationGraphViaBrowser {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'Connect-MgGraph -AccessToken requires a SecureString; OAuth access token is already in memory.')]
    param(
        [Parameter(Mandatory)]
        [string]$TenantId,

        [Parameter(Mandatory)]
        [string[]]$Scopes,

        [Parameter(Mandatory)]
        [ValidateSet('Global', 'USGov', 'USGovDoD', 'Germany', 'China')]
        [string]$Environment,

        [string]$ClientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e'
    )

    $environmentInfo = Get-HydrationGraphEnvironmentInfo -Environment $Environment
    $resolvedScopes = ConvertTo-HydrationOAuthScope -Scopes $Scopes -GraphEndpoint $environmentInfo.Endpoint

    foreach ($attempt in 1..2) {
        $tokens = Get-HydrationTokenViaBrowser `
            -ClientId $ClientId `
            -TenantId $TenantId `
            -AuthorityHost $environmentInfo.AuthorityHost `
            -Scopes $resolvedScopes

        $secureToken = ConvertTo-SecureString -String $tokens.access_token -AsPlainText -Force
        try {
            Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
            Connect-MgGraph -AccessToken $secureToken -Environment $Environment -NoWelcome -ErrorAction Stop
            return
        } catch {
            if ($attempt -eq 2) {
                throw
            }

            Write-Verbose "Browser Graph token could not connect; retrying with a fresh browser sign-in: $_"
        }
    }
}
