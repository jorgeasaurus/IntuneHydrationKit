function Invoke-HydrationOAuthTokenRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AuthorityHost,

        [Parameter(Mandatory)]
        [string]$TenantId,

        [Parameter(Mandatory)]
        [hashtable]$Body
    )

    $tokenUri = "$($AuthorityHost.TrimEnd('/'))/$TenantId/oauth2/v2.0/token"
    Invoke-RestMethod -Method POST -Uri $tokenUri -Body $Body -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
}
