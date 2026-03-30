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
        Maximum retry attempts for failed batches. Defaults to 3.
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

    $results = @()

    if ($Items.Count -eq 0) {
        return $results
    }

    $actionVerb = if ($Operation -eq 'DELETE') { 'Deleting' } else { 'Creating' }
    Write-Verbose "$actionVerb $($Items.Count) $ResultType items in batches..."

    for ($batchStart = 0; $batchStart -lt $Items.Count; $batchStart += $MaxBatchSize) {
        $batchEnd = [Math]::Min($batchStart + $MaxBatchSize, $Items.Count) - 1
        $currentBatch = $Items[$batchStart..$batchEnd]

        $pendingItems = @($currentBatch)
        $retryCount = 0

        while ($pendingItems.Count -gt 0 -and $retryCount -le $MaxRetries) {
            if ($retryCount -gt 0) {
                $delay = $RetryDelaySeconds * [Math]::Pow(2, $retryCount - 1)
                Write-Verbose "Retrying $($pendingItems.Count) failed $($Operation.ToLower())(s) after ${delay}s delay (attempt $retryCount of $MaxRetries)..."
                Start-Sleep -Seconds $delay
            }

            $batchResponse = $null
            $itemsToRetry = @()

            if ($Operation -eq 'DELETE') {
                $batchRequests = @()
                for ($i = 0; $i -lt $pendingItems.Count; $i++) {
                    $item = $pendingItems[$i]
                    $url = if ($item.Url) { $item.Url } else { "$BaseUrl/$($item.Id)" }
                    $batchRequests += @{
                        id     = ($i + 1).ToString()
                        method = "DELETE"
                        url    = $url
                    }
                }

                $batchBody = @{ requests = $batchRequests }

                try {
                    $batchResponse = Invoke-MgGraphRequest -Method POST -Uri "beta/`$batch" -Body $batchBody -ErrorAction Stop
                    Write-Verbose "Batch DELETE response received with $($batchResponse.responses.Count) responses"
                } catch {
                    if ($retryCount -lt $MaxRetries) {
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
                # POST operation - build JSON manually to avoid serialization issues
                # Filter out items with missing URLs before building the batch
                $validItems = @()
                $invalidItems = @()
                foreach ($item in $pendingItems) {
                    $url = if ($item.Url) { $item.Url } else { $BaseUrl }
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
                $batchRequestsJson = @()
                for ($i = 0; $i -lt $pendingItems.Count; $i++) {
                    $item = $pendingItems[$i]
                    $url = if ($item.Url) { $item.Url } else { $BaseUrl }
                    $requestJson = "{`"id`":`"$(($i + 1).ToString())`",`"method`":`"POST`",`"url`":`"$url`",`"headers`":{`"Content-Type`":`"application/json`"},`"body`":$($item.BodyJson)}"
                    $batchRequestsJson += $requestJson
                }

                $batchBodyJson = "{`"requests`":[" + ($batchRequestsJson -join ",") + "]}"

                try {
                    $batchResponse = Invoke-MgGraphRequest -Method POST -Uri "beta/`$batch" -Body $batchBodyJson -ContentType 'application/json' -ErrorAction Stop
                } catch {
                    if ($retryCount -lt $MaxRetries) {
                        Write-Verbose "Batch create failed, will retry: $_"
                        $itemsToRetry = $pendingItems
                    } else {
                        Write-Warning "Batch create failed: $_"
                        foreach ($item in $pendingItems) {
                            $resultParams = @{
                                Name   = $item.Name
                                Type   = $ResultType
                                Action = 'Failed'
                                Status = "Batch create failed: $_"
                            }
                            if ($item.Path) { $resultParams.Path = $item.Path }
                            $results += New-HydrationResult @resultParams
                        }
                    }
                    $pendingItems = $itemsToRetry
                    $retryCount++
                    continue
                }
            }

            # Process batch response
            if (-not $batchResponse.responses -or $batchResponse.responses.Count -eq 0) {
                Write-Warning "Batch response has no responses array for $($pendingItems.Count) items - marking as Failed"
                foreach ($item in $pendingItems) {
                    $resultParams = @{ Name = $item.Name; Type = $ResultType }
                    if ($item.Path) { $resultParams.Path = $item.Path }
                    $statusMessage = 'Batch response missing responses array'
                    Write-HydrationLog -Message "  [!] Failed: $($item.Name) - $statusMessage" -Level Warning
                    $results += New-HydrationResult @resultParams -Action 'Failed' -Status "$Operation failed: $statusMessage"
                }
                $pendingItems = @()
                continue
            }

            foreach ($resp in $batchResponse.responses) {
                # Safely map batch response ID to pending item with bounds check
                $requestIndex = $null
                $item = $null
                if ([int]::TryParse([string]$resp.id, [ref]$requestIndex)) {
                    $requestIndex = $requestIndex - 1
                    if ($requestIndex -ge 0 -and $requestIndex -lt $pendingItems.Count) {
                        $item = $pendingItems[$requestIndex]
                    }
                }

                if (-not $item) {
                    $fallbackName = "Unknown item (batch id $($resp.id))"
                    Write-HydrationLog -Message "  [!] Failed: $fallbackName - Unmatched batch response" -Level Warning
                    $results += New-HydrationResult -Name $fallbackName -Type $ResultType -Action 'Failed' -Status "$Operation failed: Unmatched batch response id='$($resp.id)'"
                    continue
                }

                Write-Verbose "Batch response for '$($item.Name)': status=$($resp.status)"

                $resultParams = @{
                    Name = $item.Name
                    Type = if ($item.Type) { $item.Type } else { $ResultType }
                }
                if ($item.Path) { $resultParams.Path = $item.Path }
                if ($item.State) { $resultParams.State = $item.State }
                if ($item.Platform) { $resultParams.Platform = $item.Platform }

                if ($Operation -eq 'DELETE') {
                    if ($resp.status -in @(200, 202, 204)) {
                        Write-HydrationLog -Message "  Deleted: $($item.Name)" -Level Info
                        $results += New-HydrationResult @resultParams -Action 'Deleted' -Status 'Success'
                    } elseif ($resp.status -eq 404) {
                        Write-HydrationLog -Message "  Skipped: $($item.Name) (already deleted)" -Level Info
                        $results += New-HydrationResult @resultParams -Action 'Skipped' -Status 'Already deleted'
                    } elseif ($resp.status -ge 500 -and $retryCount -lt $MaxRetries) {
                        Write-Verbose "Server error ($($resp.status)) for '$($item.Name)' - will retry"
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
                    } elseif ($resp.status -ge 500 -and $retryCount -lt $MaxRetries) {
                        Write-Verbose "Server error ($($resp.status)) for '$($item.Name)' - will retry"
                        $itemsToRetry += $item
                    } else {
                        $errorMessage = if ($resp.body.error.message) { $resp.body.error.message } else { "HTTP $($resp.status)" }
                        Write-HydrationLog -Message "  [!] Failed: $($item.Name) - $errorMessage" -Level Warning
                        $results += New-HydrationResult @resultParams -Action 'Failed' -Status $errorMessage
                    }
                }
            }

            $pendingItems = $itemsToRetry
            $retryCount++
        }
    }

    return $results
}
