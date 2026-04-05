function Get-GraphPagedResults {
    <#
    .SYNOPSIS
        Fetches all pages of a Graph API paginated response
    .DESCRIPTION
        Handles the @odata.nextLink pagination pattern used by Microsoft Graph API.
        Can either accumulate all results and return them, or invoke a scriptblock
        per page for streaming/processing scenarios.
    .PARAMETER Uri
        The initial Graph API URI (relative, e.g., "beta/deviceManagement/configurationPolicies")
    .PARAMETER Headers
        Optional headers to include in the request
    .PARAMETER ProcessItems
        Optional scriptblock invoked with each page's .value array. When provided,
        items are NOT accumulated — the caller handles them in the scriptblock.
    .EXAMPLE
        # Accumulate all results
        $allPolicies = Get-GraphPagedResults -Uri "beta/deviceManagement/configurationPolicies"
    .EXAMPLE
        # Process each page (streaming)
        Get-GraphPagedResults -Uri "beta/groups" -ProcessItems { param($items) $items | ForEach-Object { ... } }
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter()]
        [hashtable]$Headers,

        [Parameter()]
        [scriptblock]$ProcessItems
    )

    $results = [System.Collections.Generic.List[object]]::new()
    $listUri = $Uri
    $maxRetries = 3
    $baseRetryDelay = 2

    do {
        $params = @{
            Method      = 'GET'
            Uri         = $listUri
            ErrorAction = 'Stop'
        }
        if ($Headers) { $params['Headers'] = $Headers }

        $response = $null
        $retryCount = 0

        while ($true) {
            try {
                $response = Invoke-MgGraphRequest @params
                break
            } catch {
                # Invoke-MgGraphRequest deserializes JSON into a Dictionary which throws
                # on duplicate keys. Fall back to raw HTTP response + ConvertFrom-Json
                # (returns PSCustomObject where last-key-wins, no error).
                if ($_.Exception.Message -like '*Item has already been added*' -or
                    ($_.Exception.InnerException -and $_.Exception.InnerException.Message -like '*Item has already been added*')) {
                    Write-Verbose "Dictionary deserialization failed for '$listUri', retrying with raw HTTP response"
                    $httpResponse = Invoke-MgGraphRequest @params -OutputType HttpResponseMessage
                    $jsonContent = $httpResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                    $response = $jsonContent | ConvertFrom-Json
                    break
                }

                # Handle transient errors (429 throttling, 5xx server errors) with retry
                $httpStatus = $null
                if ($_.Exception.Response.StatusCode) {
                    $httpStatus = [int]$_.Exception.Response.StatusCode
                }
                $isRetryable = $httpStatus -in @(429, 503) -or ($httpStatus -ge 500 -and $httpStatus -lt 600)

                if ($isRetryable -and $retryCount -lt $maxRetries) {
                    $retryAfter = 0
                    if ($_.Exception.Response.Headers -and $_.Exception.Response.Headers['Retry-After']) {
                        [int]::TryParse([string]$_.Exception.Response.Headers['Retry-After'], [ref]$retryAfter) | Out-Null
                    }
                    $delay = if ($retryAfter -gt 0) { $retryAfter } else { $baseRetryDelay * [Math]::Pow(2, $retryCount) }
                    Write-Verbose "Transient error (HTTP $httpStatus) fetching '$listUri' - retrying after ${delay}s (attempt $($retryCount + 1) of $maxRetries)"
                    Start-Sleep -Seconds $delay
                    $retryCount++
                    continue
                }

                throw
            }
        }

        $responseValue = if ($null -ne $response.value) { $response.value } else { @() }

        if ($ProcessItems) {
            & $ProcessItems $responseValue
        } else {
            if ($responseValue) {
                $results.AddRange(@($responseValue))
            }
        }

        $listUri = $response.'@odata.nextLink'
    } while ($listUri)

    if (-not $ProcessItems) {
        return , $results.ToArray()
    }
}
