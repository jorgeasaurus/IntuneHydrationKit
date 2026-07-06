function Get-HydrationBatchRetryAfterSeconds {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Headers,

        [Parameter()]
        [object]$Body
    )

    $headerCandidates = @('Retry-After', 'retry-after', 'x-ms-retry-after-ms', 'X-Ms-Retry-After-Ms')
    foreach ($headerName in $headerCandidates) {
        if (-not $Headers) {
            continue
        }

        $headerValue = $null
        if ($Headers -is [System.Collections.IDictionary] -and $Headers.Contains($headerName)) {
            $headerValue = $Headers[$headerName]
        } elseif ($Headers.PSObject -and $Headers.PSObject.Properties[$headerName]) {
            $headerValue = $Headers.$headerName
        }

        if ($null -eq $headerValue) {
            continue
        }

        $parsedValue = 0
        if ([int]::TryParse([string]$headerValue, [ref]$parsedValue) -and $parsedValue -gt 0) {
            if ($headerName -like '*-ms') {
                return [Math]::Ceiling($parsedValue / 1000)
            }

            return $parsedValue
        }
    }

    $retryAfterCandidates = @(
        $Body.error.innerError.retryAfterSeconds,
        $Body.error.innerError.retryAfter,
        $Body.error.details.retryAfterSeconds,
        $Body.error.details.retryAfter
    )
    foreach ($candidate in $retryAfterCandidates) {
        $parsedValue = 0
        if ([int]::TryParse([string]$candidate, [ref]$parsedValue) -and $parsedValue -gt 0) {
            return $parsedValue
        }
    }

    return $null
}
