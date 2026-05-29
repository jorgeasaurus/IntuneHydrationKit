function New-HydrationOAuthAuthorizeUri {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$ClientId,

        [Parameter(Mandatory)]
        [string]$TenantId,

        [Parameter(Mandatory)]
        [string]$AuthorityHost,

        [Parameter(Mandatory)]
        [string]$RedirectUri,

        [Parameter(Mandatory)]
        [string[]]$Scopes,

        [Parameter(Mandatory)]
        [string]$State,

        [Parameter(Mandatory)]
        [string]$CodeChallenge,

        [Parameter()]
        [ValidateSet('login', 'none', 'consent', 'select_account')]
        [string]$Prompt = 'select_account'
    )

    $authParams = [ordered]@{
        client_id             = $ClientId
        response_type         = 'code'
        redirect_uri          = $RedirectUri
        response_mode         = 'query'
        scope                 = ($Scopes -join ' ')
        state                 = $State
        code_challenge        = $CodeChallenge
        code_challenge_method = 'S256'
        prompt                = $Prompt
    }

    $query = ($authParams.GetEnumerator() | ForEach-Object {
            "$($_.Key)=$([Uri]::EscapeDataString([string]$_.Value))"
        }) -join '&'

    return "$($AuthorityHost.TrimEnd('/'))/$TenantId/oauth2/v2.0/authorize?$query"
}
