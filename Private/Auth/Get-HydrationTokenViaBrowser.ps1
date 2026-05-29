function Get-HydrationTokenViaBrowser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ClientId,

        [Parameter(Mandatory)]
        [string]$TenantId,

        [Parameter(Mandatory)]
        [string]$AuthorityHost,

        [Parameter(Mandatory)]
        [string[]]$Scopes,

        [Parameter()]
        [switch]$ForceConsent,

        [int]$RedirectPort
    )

    if (-not $RedirectPort -or $RedirectPort -le 0) {
        $RedirectPort = Get-HydrationFreeTcpPort
    }

    $redirectUri = "http://localhost:$RedirectPort/"
    $verifier = New-HydrationCodeVerifier
    $challenge = New-HydrationCodeChallenge -Verifier $verifier
    $state = [Guid]::NewGuid().ToString('N')
    $prompt = if ($ForceConsent) { 'consent' } else { 'select_account' }

    $authUri = New-HydrationOAuthAuthorizeUri `
        -ClientId $ClientId `
        -TenantId $TenantId `
        -AuthorityHost $AuthorityHost `
        -RedirectUri $redirectUri `
        -Scopes $Scopes `
        -State $state `
        -CodeChallenge $challenge `
        -Prompt $prompt

    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add($redirectUri)
    $listener.Start()

    try {
        Write-Information (Format-HydrationDisplayMessage -Message "Opening browser for Microsoft Graph sign-in" -Style 'Info') -InformationAction Continue
        Start-Process $authUri | Out-Null

        $contextTask = $listener.GetContextAsync()
        if (-not $contextTask.Wait([TimeSpan]::FromMinutes(5))) {
            throw 'Authentication timed out after 5 minutes.'
        }

        $context = $contextTask.Result
        $code = $context.Request.QueryString['code']
        $authError = $context.Request.QueryString['error']
        $errorDescription = $context.Request.QueryString['error_description']
        $returnedState = $context.Request.QueryString['state']
        $callbackResult = Get-HydrationOAuthCallbackResult `
            -Code $code `
            -AuthError $authError `
            -ErrorDescription $errorDescription `
            -ReturnedState $returnedState `
            -ExpectedState $state

        $html = if ($callbackResult.Status -eq 'Success') {
            New-HydrationBrowserAuthResponseHtml -Status Success
        } else {
            New-HydrationBrowserAuthResponseHtml -Status Error -Message $callbackResult.Message
        }
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($html)
        $context.Response.ContentType = 'text/html; charset=utf-8'
        $context.Response.ContentLength64 = $bytes.Length
        $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        $context.Response.Close()

        if ($callbackResult.ErrorMessage) {
            throw $callbackResult.ErrorMessage
        }

        $body = @{
            client_id     = $ClientId
            grant_type    = 'authorization_code'
            code          = $code
            redirect_uri  = $redirectUri
            code_verifier = $verifier
            scope         = ($Scopes -join ' ')
        }

        Invoke-HydrationOAuthTokenRequest -AuthorityHost $AuthorityHost -TenantId $TenantId -Body $body
    } finally {
        $listener.Stop()
        $listener.Close()
    }
}
