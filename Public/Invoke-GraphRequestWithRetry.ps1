function Invoke-GraphRequestWithRetry {
    <#
    .SYNOPSIS
        Invokes a Graph API request with retry logic
    .PARAMETER Method
        HTTP method
    .PARAMETER Uri
        Graph API URI
    .PARAMETER Body
        Request body
    .PARAMETER MaxRetries
        Maximum number of retries
    .PARAMETER RetryDelaySeconds
        Initial delay between retries (uses exponential backoff)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('GET', 'POST', 'PATCH', 'PUT', 'DELETE')]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter()]
        [object]$Body,

        [Parameter()]
        [int]$MaxRetries = 3,

        [Parameter()]
        [int]$RetryDelaySeconds = 2
    )

    $attempt = 0
    $lastError = $null

    while ($attempt -lt $MaxRetries) {
        $attempt++
        try {
            $params = @{
                Method = $Method
                Uri = $Uri
                ErrorAction = 'Stop'
            }

            if ($Body) {
                $params['Body'] = $Body | ConvertTo-Json -Depth 10
                $params['ContentType'] = 'application/json'
            }

            $response = Invoke-MgGraphRequest @params
            return $response
        }
        catch {
            $lastError = $_
            $statusCode = $_.Exception.Response.StatusCode.value__

            # Check for retryable errors (429, 503, 504)
            if ($statusCode -in @(429, 503, 504)) {
                $delay = $RetryDelaySeconds * [Math]::Pow(2, $attempt - 1)

                # Check for Retry-After header
                $retryAfter = $_.Exception.Response.Headers['Retry-After']
                if ($retryAfter) {
                    $delay = [int]$retryAfter
                }

                Write-HydrationLog -Message "Request failed with $statusCode. Retrying in $delay seconds (attempt $attempt of $MaxRetries)" -Level Warning
                Start-Sleep -Seconds $delay
            }
            else {
                # Non-retryable error
                throw
            }
        }
    }

    Write-HydrationLog -Message "Request failed after $MaxRetries attempts" -Level Error
    throw $lastError
}
