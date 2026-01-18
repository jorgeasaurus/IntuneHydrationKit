function Invoke-GraphBatchOperation {
    <#
    .SYNOPSIS
        Executes Graph API batch requests with retry logic and standardized result handling
    .DESCRIPTION
        Internal helper that handles batched Graph API requests with exponential backoff retry
        for transient server errors. Returns results in standardized New-HydrationResult format.
    .PARAMETER Items
        Array of items to process. Each item must be a hashtable with at least 'Name' key.
        For DELETE operations: must include 'Id' key.
        For POST operations: must include 'BodyJson' key with JSON string payload.
    .PARAMETER Operation
        The HTTP operation: 'POST' for creation or 'DELETE' for removal.
    .PARAMETER BaseUrl
        The Graph API URL path (without /beta prefix), e.g., '/deviceAppManagement/mobileApps'
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

        [Parameter(Mandatory)]
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
                    $batchRequests += @{
                        id     = ($i + 1).ToString()
                        method = "DELETE"
                        url    = "$BaseUrl/$($item.Id)"
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
                $batchRequestsJson = @()
                for ($i = 0; $i -lt $pendingItems.Count; $i++) {
                    $item = $pendingItems[$i]
                    $requestJson = "{`"id`":`"$(($i + 1).ToString())`",`"method`":`"POST`",`"url`":`"$BaseUrl`",`"headers`":{`"Content-Type`":`"application/json`"},`"body`":$($item.BodyJson)}"
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
                Write-Warning "Batch response has no responses array - assuming success for $($pendingItems.Count) items"
                foreach ($item in $pendingItems) {
                    $resultParams = @{ Name = $item.Name; Type = $ResultType }
                    if ($item.Path) { $resultParams.Path = $item.Path }
                    $action = if ($Operation -eq 'DELETE') { 'Deleted' } else { 'Created' }
                    Write-HydrationLog -Message "  ${action}: $($item.Name)" -Level Info
                    $results += New-HydrationResult @resultParams -Action $action -Status 'Success'
                }
                $pendingItems = @()
                continue
            }

            foreach ($resp in $batchResponse.responses) {
                $requestIndex = [int]$resp.id - 1
                $item = $pendingItems[$requestIndex]

                Write-Verbose "Batch response for '$($item.Name)': status=$($resp.status)"

                $resultParams = @{
                    Name = $item.Name
                    Type = $ResultType
                }
                if ($item.Path) { $resultParams.Path = $item.Path }
                if ($item.State) { $resultParams.State = $item.State }

                if ($Operation -eq 'DELETE') {
                    if ($resp.status -in @(200, 202, 204)) {
                        Write-HydrationLog -Message "Deleted: $($item.Name)" -Level Info
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
                    if ($resp.status -eq 201) {
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
