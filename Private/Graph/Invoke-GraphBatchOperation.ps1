function Invoke-GraphBatchOperation {
    <#
    .SYNOPSIS
        Executes Graph API batch requests with retry logic and standardized result handling
    .DESCRIPTION
        Internal helper that handles batched Graph API requests with exponential backoff retry
        for transient server errors. Returns results in standardized New-HydrationResult format.
    .PARAMETER Items
        Array of items to process. Each item must be a hashtable with at least 'Name' key.
        For DELETE operations: must include 'Id' key (or 'Url' for the full batch URL path).
        For POST operations: must include 'BodyJson' key with JSON string payload.
        Optional keys: 'Url' (overrides BaseUrl for per-item endpoints), 'Type' (overrides ResultType),
        'Path' (source file path), 'State' (e.g., CA policy state).
    .PARAMETER Operation
        The HTTP operation: 'POST' for creation or 'DELETE' for removal.
    .PARAMETER BaseUrl
        The Graph API URL path (without /beta prefix), e.g., '/deviceAppManagement/mobileApps'.
        Optional if each item provides its own 'Url' key.
    .PARAMETER ResultType
        The Type value to use in New-HydrationResult (e.g., 'MobileApp', 'AppProtection')
    .PARAMETER MaxBatchSize
        Maximum items per batch request. Defaults to 10.
    .PARAMETER MaxRetries
        Maximum retries after the initial attempt for failed batches. Defaults to 3.
    .PARAMETER RetryDelaySeconds
        Base delay between retries (doubles with each retry). Defaults to 2.
    .EXAMPLE
        $items = @(@{ Name = 'App1'; Id = 'guid-1' }, @{ Name = 'App2'; Id = 'guid-2' })
        Invoke-GraphBatchOperation -Items $items -Operation 'DELETE' -BaseUrl '/deviceAppManagement/mobileApps' -ResultType 'MobileApp'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Items,

        [Parameter(Mandatory)]
        [ValidateSet('POST', 'DELETE')]
        [string]$Operation,

        [Parameter()]
        [string]$BaseUrl,

        [Parameter(Mandatory)]
        [string]$ResultType,

        [Parameter()]
        [int]$MaxBatchSize = $(if ($script:MaxBatchSize) { $script:MaxBatchSize } else { 10 }),

        [Parameter()]
        [int]$MaxRetries = 3,

        [Parameter()]
        [int]$RetryDelaySeconds = 2
    )

    function Test-IsThrottleSensitiveWrite {
        param(
            [Parameter()]
            [string]$Url
        )

        return $Operation -eq 'POST' -and $Url -eq '/deviceManagement/intents'
    }

    function Get-ItemUrl {
        param(
            [Parameter(Mandatory)]
            [hashtable]$Item,

            [Parameter(Mandatory)]
            [string]$OperationName,

            [Parameter()]
            [string]$DefaultUrl
        )

        if ($Item.Url) {
            return $Item.Url
        }

        if ($OperationName -eq 'DELETE') {
            return "$DefaultUrl/$($Item.Id)"
        }

        return $DefaultUrl
    }

    function Test-IsIndeterminateCreateStatus {
        param(
            [Parameter(Mandatory)]
            [int]$Status
        )

        return $Status -ge 500 -and $Status -lt 600
    }

    function New-ItemResultParams {
        param(
            [Parameter(Mandatory)]
            [hashtable]$Item
        )

        $resultParams = @{
            Name = $Item.Name
            Type = if ($Item.Type) { $Item.Type } else { $ResultType }
        }

        if ($Item.Path) { $resultParams.Path = $Item.Path }
        if ($Item.State) { $resultParams.State = $Item.State }
        if ($Item.Platform) { $resultParams.Platform = $Item.Platform }

        return $resultParams
    }

    function Get-BatchResponseList {
        param(
            [Parameter()]
            [object]$BatchResponse
        )

        if ($BatchResponse -and $BatchResponse.responses) {
            return @($BatchResponse.responses)
        }

        return @()
    }

    $results = @()

    if ($Items.Count -eq 0) {
        return $results
    }

    $containsThrottleSensitiveWrites = $false
    foreach ($item in $Items) {
        $resolvedUrl = Get-ItemUrl -Item $item -OperationName $Operation -DefaultUrl $BaseUrl
        if (Test-IsThrottleSensitiveWrite -Url $resolvedUrl) {
            $containsThrottleSensitiveWrites = $true
            break
        }
    }

    $effectiveMaxRetries = if ($containsThrottleSensitiveWrites) { [Math]::Max($MaxRetries, 5) } else { $MaxRetries }
    $baseRetryDelaySeconds = if ($containsThrottleSensitiveWrites) { [Math]::Max($RetryDelaySeconds, 15) } else { $RetryDelaySeconds }

    $actionVerb = if ($Operation -eq 'DELETE') { 'Deleting' } else { 'Creating' }
    Write-Verbose "$actionVerb $($Items.Count) $ResultType items in batches..."
    if ($containsThrottleSensitiveWrites) {
        Write-Verbose "Using conservative retry policy for throttling-prone deviceManagement/intents writes"
    }

    for ($batchStart = 0; $batchStart -lt $Items.Count; $batchStart += $MaxBatchSize) {
        $batchEnd = [Math]::Min($batchStart + $MaxBatchSize, $Items.Count) - 1
        $currentBatch = $Items[$batchStart..$batchEnd]

        $pendingItems = @($currentBatch)
        $retryCount = 0

        while ($pendingItems.Count -gt 0 -and $retryCount -le $effectiveMaxRetries) {
            if ($retryCount -gt 0) {
                # Honor Retry-After from previous throttled responses; fall back to exponential backoff
                $maxRetryAfter = 0
                foreach ($item in $pendingItems) {
                    if ($item.RetryAfter) {
                        $parsedRetryAfter = 0
                        if ([int]::TryParse([string]$item.RetryAfter, [ref]$parsedRetryAfter) -and $parsedRetryAfter -gt $maxRetryAfter) {
                            $maxRetryAfter = $parsedRetryAfter
                        }
                        $item.Remove('RetryAfter')
                    }
                }
                $delay = if ($maxRetryAfter -gt 0) { $maxRetryAfter } else { $baseRetryDelaySeconds * [Math]::Pow(2, $retryCount - 1) }
                $delaySource = if ($maxRetryAfter -gt 0) { 'Retry-After header' } else { 'exponential backoff' }
                Write-Verbose "Retrying $($pendingItems.Count) failed $($Operation.ToLower())(s) after ${delay}s delay ($delaySource, attempt $retryCount of $effectiveMaxRetries)..."
                Start-Sleep -Seconds $delay
            }

            $batchResponse = $null
            $itemsToRetry = @()
            $batchEntries = @()

            if ($Operation -eq 'DELETE') {
                for ($i = 0; $i -lt $pendingItems.Count; $i++) {
                    $item = $pendingItems[$i]
                    $request = @{
                        id     = ($i + 1).ToString()
                        method = "DELETE"
                        url    = Get-ItemUrl -Item $item -OperationName $Operation -DefaultUrl $BaseUrl
                    }
                    $batchEntries += [pscustomobject]@{
                        Id      = [string]$request.id
                        Request = $request
                        Item    = $item
                        Index   = $i
                    }
                }

                $batchBody = @{ requests = @($batchEntries | ForEach-Object { $_.Request }) }

                try {
                    $batchResponse = Invoke-MgGraphRequest -Method POST -Uri "beta/`$batch" -Body $batchBody -ErrorAction Stop
                    Write-Verbose "Batch DELETE response received with $($batchResponse.responses.Count) responses"
                } catch {
                    if ($retryCount -lt $effectiveMaxRetries) {
                        Write-Verbose "Batch delete failed, will retry: $_"
                        $itemsToRetry = $pendingItems
                    } else {
                        Write-Warning "Batch delete failed: $_"
                        foreach ($item in $pendingItems) {
                            $results += New-HydrationResult -Name $item.Name -Type $ResultType -Action 'Failed' -Status "Batch delete failed: $_"
                        }
                    }
                    $pendingItems = $itemsToRetry
                    $retryCount++
                    continue
                }
            } else {
                # POST operation
                # Filter out items with missing URLs before building the batch
                $validItems = @()
                $invalidItems = @()
                foreach ($item in $pendingItems) {
                    $url = Get-ItemUrl -Item $item -OperationName $Operation -DefaultUrl $BaseUrl
                    if ([string]::IsNullOrWhiteSpace($url)) {
                        $invalidItems += $item
                    } else {
                        $validItems += $item
                    }
                }

                if ($invalidItems.Count -gt 0) {
                    foreach ($item in $invalidItems) {
                        Write-HydrationLog -Message "  [!] Failed: $($item.Name) - No API endpoint URL resolved" -Level Warning
                        $resultParams = @{ Name = $item.Name; Type = if ($item.Type) { $item.Type } else { $ResultType } }
                        if ($item.Path) { $resultParams.Path = $item.Path }
                        $results += New-HydrationResult @resultParams -Action 'Failed' -Status 'No API endpoint URL resolved'
                    }
                }

                if ($validItems.Count -eq 0) {
                    $pendingItems = @()
                    continue
                }

                $pendingItems = $validItems
                for ($i = 0; $i -lt $pendingItems.Count; $i++) {
                    $item = $pendingItems[$i]
                    $url = Get-ItemUrl -Item $item -OperationName $Operation -DefaultUrl $BaseUrl
                    $request = @{
                        id      = ($i + 1).ToString()
                        method  = "POST"
                        url     = $url
                        headers = @{ "Content-Type" = "application/json" }
                        body    = $item.BodyJson | ConvertFrom-Json
                    }
                    $batchEntries += [pscustomobject]@{
                        Id      = [string]$request.id
                        Request = $request
                        Item    = $item
                        Index   = $i
                    }
                }

                $batchBodyJson = @{ requests = @($batchEntries | ForEach-Object { $_.Request }) } | ConvertTo-Json -Depth 100 -Compress

                try {
                    $batchResponse = Invoke-MgGraphRequest -Method POST -Uri "beta/`$batch" -Body $batchBodyJson -ContentType 'application/json' -ErrorAction Stop
                } catch {
                    $statusCode = Get-GraphStatusCode -ErrorRecord $_
                    if ($statusCode -eq 429) {
                        if ($retryCount -lt $effectiveMaxRetries) {
                            Write-Verbose "Batch create was throttled, will retry: $_"
                            $itemsToRetry = $pendingItems
                        } else {
                            $statusMessage = "Create failed: batch request throttled after retries: $_"
                            Write-Warning $statusMessage
                            foreach ($item in $pendingItems) {
                                $resultParams = New-ItemResultParams -Item $item
                                Write-HydrationLog -Message "  [!] Failed: $($item.Name) - $statusMessage" -Level Warning
                                $results += New-HydrationResult @resultParams -Action 'Failed' -Status $statusMessage
                            }
                        }
                        $pendingItems = $itemsToRetry
                        $retryCount++
                        continue
                    }

                    $statusMessage = "Create indeterminate: batch request failed before responses; not retried to avoid duplicate creation: $_"
                    Write-Warning $statusMessage
                    foreach ($item in $pendingItems) {
                        $resultParams = New-ItemResultParams -Item $item
                        Write-HydrationLog -Message "  [!] Failed: $($item.Name) - $statusMessage" -Level Warning
                        $results += New-HydrationResult @resultParams -Action 'Failed' -Status $statusMessage
                    }
                    $pendingItems = $itemsToRetry
                    $retryCount++
                    continue
                }
            }

            # Process batch response
            $batchResponses = @(Get-BatchResponseList -BatchResponse $batchResponse)
            if ($batchResponses.Count -eq 0) {
                Write-Warning "Batch response has no responses array for $($pendingItems.Count) items"
            }

            $responseState = Resolve-HydrationBatchResponse -BatchEntries $batchEntries -Responses $batchResponses

            foreach ($unmatchedResponse in $responseState.Unmatched) {
                $resp = $unmatchedResponse.Response
                $fallbackName = "Unknown item (batch id $($resp.id))"
                Write-HydrationLog -Message "  [!] Failed: $fallbackName - Unmatched batch response" -Level Warning
                $results += New-HydrationResult -Name $fallbackName -Type $ResultType -Action 'Failed' -Status "$Operation failed: Unmatched batch response id='$($resp.id)'"
            }

            foreach ($resolvedResponse in $responseState.Matched) {
                $resp = $resolvedResponse.Response
                $item = $resolvedResponse.Item

                Write-Verbose "Batch response for '$($item.Name)': status=$($resp.status)"

                $resultParams = New-ItemResultParams -Item $item

                if ($Operation -eq 'DELETE') {
                    if ($resp.status -in @(200, 202, 204)) {
                        Write-HydrationLog -Message "  Deleted: $($item.Name)" -Level Info
                        $results += New-HydrationResult @resultParams -Action 'Deleted' -Status 'Success'
                    } elseif ($resp.status -eq 404) {
                        Write-HydrationLog -Message "  Skipped: $($item.Name) (already deleted)" -Level Info
                        $results += New-HydrationResult @resultParams -Action 'Skipped' -Status 'Already deleted'
                    } elseif ((Test-HydrationBatchStatusRetryable -Status $resp.status -Operation $Operation) -and $retryCount -lt $effectiveMaxRetries) {
                        Write-Verbose "Retryable error ($($resp.status)) for '$($item.Name)' - will retry"
                        $retryAfterSeconds = Get-HydrationBatchRetryAfterSeconds -Headers $resp.headers -Body $resp.body
                        if ($retryAfterSeconds) { $item.RetryAfter = $retryAfterSeconds }
                        $itemsToRetry += $item
                    } else {
                        $errorMessage = if ($resp.body.error.message) { $resp.body.error.message } else { "HTTP $($resp.status)" }
                        Write-HydrationLog -Message "  [!] Failed: $($item.Name) - $errorMessage" -Level Warning
                        $results += New-HydrationResult @resultParams -Action 'Failed' -Status "Delete failed: $errorMessage"
                    }
                } else {
                    # POST response handling
                    if ($resp.status -in @(200, 201)) {
                        Write-HydrationLog -Message "  Created: $($item.Name)" -Level Info
                        $resultParams.Id = $resp.body.id
                        $results += New-HydrationResult @resultParams -Action 'Created' -Status 'Success'
                    } elseif ($resp.status -eq 409) {
                        Write-HydrationLog -Message "  Skipped: $($item.Name) (race condition)" -Level Info
                        $results += New-HydrationResult @resultParams -Action 'Skipped' -Status 'Already exists (race condition)'
                    } elseif ((Test-HydrationBatchStatusRetryable -Status $resp.status -Operation $Operation) -and $retryCount -lt $effectiveMaxRetries) {
                        Write-Verbose "Retryable error ($($resp.status)) for '$($item.Name)' - will retry"
                        $retryAfterSeconds = Get-HydrationBatchRetryAfterSeconds -Headers $resp.headers -Body $resp.body
                        if ($retryAfterSeconds) { $item.RetryAfter = $retryAfterSeconds }
                        $itemsToRetry += $item
                    } else {
                        $errorMessage = if ($resp.body.error.message) { $resp.body.error.message } else { "HTTP $($resp.status)" }
                        if (Test-IsIndeterminateCreateStatus -Status $resp.status) {
                            $statusMessage = "Create indeterminate: $errorMessage; not retried to avoid duplicate creation"
                        } else {
                            $statusMessage = $errorMessage
                        }
                        Write-HydrationLog -Message "  [!] Failed: $($item.Name) - $statusMessage" -Level Warning
                        $results += New-HydrationResult @resultParams -Action 'Failed' -Status $statusMessage
                    }
                }
            }

            # Retry or fail any pending items missing from the batch response
            foreach ($missingRequest in $responseState.Missing) {
                $missingItem = $missingRequest.Item
                if ($Operation -eq 'DELETE' -and $retryCount -lt $effectiveMaxRetries) {
                    Write-Verbose "Missing response for '$($missingItem.Name)' - will retry"
                    $itemsToRetry += $missingItem
                } else {
                    $resultParams = New-ItemResultParams -Item $missingItem
                    if ($Operation -eq 'POST') {
                        $statusMessage = 'Create indeterminate: No response received from Graph API; not retried to avoid duplicate creation'
                    } else {
                        $statusMessage = 'Delete failed: No response received from Graph API'
                    }
                    Write-HydrationLog -Message "  [!] Failed: $($missingItem.Name) - $statusMessage" -Level Warning
                    $results += New-HydrationResult @resultParams -Action 'Failed' -Status $statusMessage
                }
            }

            $pendingItems = $itemsToRetry
            $retryCount++
        }
    }

    return $results
}
