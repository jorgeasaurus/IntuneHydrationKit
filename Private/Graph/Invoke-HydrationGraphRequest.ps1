function Invoke-HydrationGraphRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'DELETE')]
        [string]$Method,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Uri,

        [Parameter()]
        [AllowNull()]
        [object]$Body,

        [Parameter()]
        [string]$ContentType = 'application/json',

        [Parameter()]
        [int]$MaxRetries = 3,

        [Parameter()]
        [int]$RetryDelaySeconds = 2
    )

    function Resolve-GraphUri {
        param(
            [Parameter(Mandatory)]
            [string]$RawUri
        )

        if ([string]::IsNullOrWhiteSpace($RawUri)) {
            return $RawUri
        }

        if ($RawUri -match '^https?://') {
            $graphEndpoint = if ($script:GraphEndpoint) {
                $script:GraphEndpoint.TrimEnd('/')
            } else {
                'https://graph.microsoft.com'
            }

            if ($RawUri.StartsWith($graphEndpoint, [System.StringComparison]::OrdinalIgnoreCase)) {
                return ($RawUri.Substring($graphEndpoint.Length)).TrimStart('/')
            }

            return $RawUri
        }

        return $RawUri.TrimStart('/')
    }

    function Get-GraphUriForLogging {
        param(
            [Parameter(Mandatory)]
            [string]$RawUri
        )

        $uriSegments = $RawUri -split '\?', 2
        if ($uriSegments.Count -eq 1) {
            return $uriSegments[0]
        }

        $queryKeys = foreach ($pair in ($uriSegments[1] -split '&')) {
            if ([string]::IsNullOrWhiteSpace($pair)) {
                continue
            }

            $queryPair = $pair -split '=', 2
            '{0}=...' -f $queryPair[0]
        }

        return '{0}?{1}' -f $uriSegments[0], ($queryKeys -join '&')
    }

    function Get-GraphBodySummary {
        param(
            [Parameter()]
            [AllowNull()]
            [object]$Value,

            [Parameter()]
            [string]$ResolvedContentType
        )

        if ($null -eq $Value) {
            return 'Body=None'
        }

        if ($Value -is [string]) {
            return "Body=String(Length=$($Value.Length), ContentType='$ResolvedContentType')"
        }

        if ($Value -is [System.Collections.IDictionary]) {
            $bodyKeys = @($Value.Keys)
            return "Body=Dictionary(KeyCount=$($bodyKeys.Count), Keys='$((@($bodyKeys | Select-Object -First 8)) -join ', ')')"
        }

        $propertyNames = @($Value.PSObject.Properties.Name)
        if ($propertyNames.Count -gt 0) {
            return "Body=Object(Type='$($Value.GetType().FullName)', PropertyCount=$($propertyNames.Count), Properties='$((@($propertyNames | Select-Object -First 8)) -join ', ')')"
        }

        return "Body=Object(Type='$($Value.GetType().FullName)')"
    }

    function Get-RetryDelay {
        param(
            [Parameter(Mandatory)]
            [System.Management.Automation.ErrorRecord]$ErrorRecord,

            [Parameter(Mandatory)]
            [int]$Attempt,

            [Parameter(Mandatory)]
            [int]$BaseDelaySeconds
        )

        $headerCandidates = @(
            $ErrorRecord.Exception.ResponseHeaders,
            $ErrorRecord.Exception.Response.Headers,
            $ErrorRecord.Exception.Headers
        )

        foreach ($headers in $headerCandidates) {
            if (-not $headers) {
                continue
            }

            foreach ($headerName in @('Retry-After', 'retry-after')) {
                $headerValue = $null
                if ($headers -is [System.Collections.IDictionary] -and $headers.Contains($headerName)) {
                    $headerValue = $headers[$headerName]
                } elseif ($headers.PSObject -and $headers.PSObject.Properties[$headerName]) {
                    $headerValue = $headers.$headerName
                }

                $parsedValue = 0
                if ([int]::TryParse([string]$headerValue, [ref]$parsedValue) -and $parsedValue -gt 0) {
                    return $parsedValue
                }
            }
        }

        return $BaseDelaySeconds * [Math]::Pow(2, $Attempt - 1)
    }

    function Resolve-GraphErrorRecord {
        param(
            [Parameter(Mandatory)]
            [System.Management.Automation.ErrorRecord]$ErrorRecord
        )

        $candidateRecords = @(
            $ErrorRecord,
            $ErrorRecord.Exception.ErrorRecord,
            $ErrorRecord.Exception.InnerException.ErrorRecord
        )

        foreach ($candidateRecord in $candidateRecords) {
            if ($null -eq $candidateRecord) {
                continue
            }

            $candidateStatusCode = Get-GraphStatusCode -ErrorRecord $candidateRecord
            if ($null -ne $candidateStatusCode) {
                return $candidateRecord
            }
        }

        return $ErrorRecord
    }

    $resolvedUri = Resolve-GraphUri -RawUri $Uri
    $uriForLogging = Get-GraphUriForLogging -RawUri $resolvedUri
    $invokeParams = @{
        Method      = $Method
        Uri         = $resolvedUri
        ErrorAction = 'Stop'
    }

    if ($PSBoundParameters.ContainsKey('Body')) {
        if ($Body -is [string]) {
            $invokeParams['Body'] = $Body
            if ($ContentType) {
                $invokeParams['ContentType'] = $ContentType
            }
        } else {
            $invokeParams['Body'] = $Body
        }
    }

    $bodySummary = Get-GraphBodySummary -Value $Body -ResolvedContentType $ContentType
    Write-Debug "Invoking Graph request Method='$Method', Uri='$uriForLogging', $bodySummary."

    # MaxRetries means retries after the initial attempt.
    for ($attempt = 0; $attempt -le $MaxRetries; $attempt++) {
        try {
            return Invoke-MgGraphRequest @invokeParams
        } catch {
            $graphErrorRecord = Resolve-GraphErrorRecord -ErrorRecord $_
            $statusCode = Get-GraphStatusCode -ErrorRecord $graphErrorRecord
            $isRetryableStatusCode = $null -ne $statusCode -and ($statusCode -eq 429 -or ($statusCode -ge 500 -and $statusCode -lt 600))
            $attemptNumber = $attempt + 1
            Write-Debug "Graph request failed Method='$Method', Uri='$uriForLogging', StatusCode='$statusCode', Attempt=$attemptNumber, MaxRetries=$MaxRetries, Retryable=$isRetryableStatusCode, Error='$($_.Exception.Message)'."
            if (-not $isRetryableStatusCode -or $attempt -ge $MaxRetries) {
                throw
            }

            $retryNumber = $attempt + 1
            $delaySeconds = Get-RetryDelay -ErrorRecord $graphErrorRecord -Attempt $retryNumber -BaseDelaySeconds $RetryDelaySeconds
            Write-Verbose "Graph request failed with HTTP $statusCode. Retrying in $delaySeconds second(s) (retry $retryNumber of $MaxRetries)."
            Start-Sleep -Seconds $delaySeconds
        }
    }
}
