function Get-HydrationTenantIdFromAccessToken {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [AllowNull()]
        [string]$AccessToken
    )

    if ([string]::IsNullOrWhiteSpace($AccessToken)) {
        return $null
    }

    $tokenParts = $AccessToken -split '\.'
    if ($tokenParts.Count -lt 2) {
        return $null
    }

    $payload = $tokenParts[1].Replace('-', '+').Replace('_', '/')
    switch ($payload.Length % 4) {
        2 { $payload += '==' }
        3 { $payload += '=' }
        0 { }
        default { return $null }
    }

    try {
        $payloadJson = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($payload))
        $claims = $payloadJson | ConvertFrom-Json -ErrorAction Stop
        if ($claims.tid -match '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') {
            return $claims.tid
        }
    } catch {
        return $null
    }

    return $null
}
