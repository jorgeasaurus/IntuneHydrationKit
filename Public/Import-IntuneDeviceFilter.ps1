function Import-IntuneDeviceFilter {
    <#
    .SYNOPSIS
        Creates device filters for Intune from templates
    .DESCRIPTION
        Reads JSON templates from Templates/Filters and creates device filters via Graph API.
        Filters can be used to target or exclude devices from policy assignments.
    .PARAMETER TemplatePath
        Path to the filter template directory (defaults to Templates/Filters)
    .PARAMETER RemoveExisting
        If specified, removes existing filters created by this kit instead of creating new ones
    .PARAMETER Platform
        Filter templates by platform. Valid values: Windows, macOS, iOS, Android, All.
        Defaults to 'All' which imports all filter templates regardless of platform.
        Note: Linux device filters are not currently supported by Intune.
    .EXAMPLE
        Import-IntuneDeviceFilter
    .EXAMPLE
        Import-IntuneDeviceFilter -TemplatePath ./MyFilters
    .EXAMPLE
        Import-IntuneDeviceFilter -Platform Windows,macOS
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [string]$TemplatePath,

        [Parameter()]
        [ValidateSet('Windows', 'macOS', 'iOS', 'Android', 'All')]
        [string[]]$Platform = @('All'),

        [Parameter()]
        [switch]$RemoveExisting
    )

    if (-not $TemplatePath) {
        $TemplatePath = Join-Path -Path $script:TemplatesPath -ChildPath "Filters"
    }

    if (-not (Test-Path -Path $TemplatePath)) {
        Write-Warning "Filter template directory not found: $TemplatePath"
        return @()
    }

    $templateFiles = Get-FilteredTemplates -Path $TemplatePath -Platform $Platform -FilterMode 'Prefix' -Recurse -ResourceType "filter template"

    if (-not $templateFiles -or $templateFiles.Count -eq 0) {
        Write-Warning "No filter templates found in: $TemplatePath"
        return @()
    }

    $results = @()

    # Prefetch existing filters with pagination (OData filter on displayName not supported for this endpoint)
    # Store full filter objects so we can check descriptions later
    $existingFilters = @{}
    try {
        $listUri = "beta/deviceManagement/assignmentFilters?`$select=id,displayName,description"
        do {
            $existingFiltersResponse = Invoke-MgGraphRequest -Method GET -Uri $listUri -ErrorAction Stop
            foreach ($existingFilter in $existingFiltersResponse.value) {
                if (-not $existingFilters.ContainsKey($existingFilter.displayName)) {
                    $existingFilters[$existingFilter.displayName] = @{
                        Id          = $existingFilter.id
                        Description = $existingFilter.description
                    }
                }
            }
            $listUri = $existingFiltersResponse.'@odata.nextLink'
        } while ($listUri)
    } catch {
        Write-Warning "Could not retrieve existing filters: $_"
        $existingFilters = @{}
    }

    # Build a simple name->id lookup for backwards compatibility in the import section
    $existingFilterNames = @{}
    foreach ($key in $existingFilters.Keys) {
        $existingFilterNames[$key] = $existingFilters[$key].Id
    }

    # Remove existing filters if requested
    # SAFETY: Only delete filters that have "Imported by Intune Hydration Kit" in description
    if ($RemoveExisting) {
        $maxBatchSize = if ($script:MaxBatchSize) { $script:MaxBatchSize } else { 10 }

        # Collect filters to delete (only those with hydration marker)
        $filtersToDelete = @()
        foreach ($filterName in $existingFilters.Keys) {
            $filterInfo = $existingFilters[$filterName]

            # Safety check: Only delete if created by this kit (has hydration marker in description)
            if (-not (Test-HydrationKitObject -Description $filterInfo.Description -ObjectName $filterName)) {
                Write-Verbose "Skipping '$filterName' - not created by Intune Hydration Kit"
                continue
            }

            $filtersToDelete += @{
                Name = $filterName
                Id   = $filterInfo.Id
            }
        }

        if ($filtersToDelete.Count -eq 0) {
            Write-Verbose "No device filters found to delete"
            return $results
        }

        # Handle WhatIf mode
        if ($WhatIfPreference) {
            foreach ($filter in $filtersToDelete) {
                Write-HydrationLog -Message "  WouldDelete: $($filter.Name)" -Level Info
                $results += New-HydrationResult -Name $filter.Name -Type 'DeviceFilter' -Action 'WouldDelete' -Status 'DryRun'
            }
            return $results
        }

        # Batch delete filters with retry logic
        $maxRetries = 3
        $retryDelaySeconds = 2
        Write-Verbose "Deleting $($filtersToDelete.Count) device filters in batches..."

        for ($batchStart = 0; $batchStart -lt $filtersToDelete.Count; $batchStart += $maxBatchSize) {
            $batchEnd = [Math]::Min($batchStart + $maxBatchSize, $filtersToDelete.Count) - 1
            $currentBatch = $filtersToDelete[$batchStart..$batchEnd]

            # Track which items need retry
            $pendingItems = @($currentBatch)
            $retryCount = 0

            while ($pendingItems.Count -gt 0 -and $retryCount -le $maxRetries) {
                if ($retryCount -gt 0) {
                    $delay = $retryDelaySeconds * [Math]::Pow(2, $retryCount - 1)
                    Write-Verbose "Retrying $($pendingItems.Count) failed delete(s) after ${delay}s delay (attempt $retryCount of $maxRetries)..."
                    Start-Sleep -Seconds $delay
                }

                $batchRequests = @()
                for ($i = 0; $i -lt $pendingItems.Count; $i++) {
                    $filter = $pendingItems[$i]
                    $batchRequests += @{
                        id     = ($i + 1).ToString()
                        method = "DELETE"
                        url    = "/deviceManagement/assignmentFilters/$($filter.Id)"
                    }
                }

                $batchBody = @{ requests = $batchRequests }
                $itemsToRetry = @()

                try {
                    $batchResponse = Invoke-MgGraphRequest -Method POST -Uri "beta/`$batch" -Body $batchBody -ErrorAction Stop

                    foreach ($resp in $batchResponse.responses) {
                        $requestIndex = [int]$resp.id - 1
                        $filter = $pendingItems[$requestIndex]

                        if ($resp.status -eq 204 -or $resp.status -eq 200) {
                            Write-HydrationLog -Message "  Deleted: $($filter.Name)" -Level Info
                            $results += New-HydrationResult -Name $filter.Name -Type 'DeviceFilter' -Action 'Deleted' -Status 'Success'
                        } elseif ($resp.status -eq 404) {
                            Write-HydrationLog -Message "  Skipped: $($filter.Name) (already deleted)" -Level Info
                            $results += New-HydrationResult -Name $filter.Name -Type 'DeviceFilter' -Action 'Skipped' -Status 'Already deleted'
                        } elseif ($resp.status -ge 500 -and $retryCount -lt $maxRetries) {
                            # Server error - queue for retry
                            Write-Verbose "Server error ($($resp.status)) for '$($filter.Name)' - will retry"
                            $itemsToRetry += $filter
                        } else {
                            $errorMessage = if ($resp.body.error.message) { $resp.body.error.message } else { "HTTP $($resp.status)" }
                            Write-HydrationLog -Message "  [!] Failed: $($filter.Name) - $errorMessage" -Level Warning
                            $results += New-HydrationResult -Name $filter.Name -Type 'DeviceFilter' -Action 'Failed' -Status "Delete failed: $errorMessage"
                        }
                    }
                } catch {
                    if ($retryCount -lt $maxRetries) {
                        Write-Verbose "Batch delete failed, will retry: $_"
                        $itemsToRetry = $pendingItems
                    } else {
                        Write-Warning "Batch delete failed: $_"
                        foreach ($filter in $pendingItems) {
                            $results += New-HydrationResult -Name $filter.Name -Type 'DeviceFilter' -Action 'Failed' -Status "Batch delete failed: $_"
                        }
                    }
                }

                $pendingItems = $itemsToRetry
                $retryCount++
            }
        }

        return $results
    }

    # Collect all filters from templates
    $filtersToCreate = @()
    foreach ($templateFile in $templateFiles) {
        try {
            $template = Get-Content -Path $templateFile.FullName -Raw -Encoding utf8 | ConvertFrom-Json

            # Each template file contains a "filters" array
            if (-not $template.filters) {
                Write-Warning "Template missing 'filters' array: $($templateFile.FullName)"
                $results += New-HydrationResult -Name $templateFile.Name -Path $templateFile.FullName -Type 'DeviceFilter' -Action 'Failed' -Status "Missing 'filters' array"
                continue
            }

            foreach ($filter in $template.filters) {
                # Validate required properties
                if (-not $filter.displayName) {
                    Write-Warning "Filter missing displayName in: $($templateFile.FullName)"
                    continue
                }
                if (-not $filter.platform) {
                    Write-Warning "Filter '$($filter.displayName)' missing platform in: $($templateFile.FullName)"
                    continue
                }
                if (-not $filter.rule) {
                    Write-Warning "Filter '$($filter.displayName)' missing rule in: $($templateFile.FullName)"
                    continue
                }

                # Check if filter already exists using pre-fetched list
                if ($existingFilterNames.ContainsKey($filter.displayName)) {
                    Write-HydrationLog -Message "  Skipped: $($filter.displayName)" -Level Info
                    $results += New-HydrationResult -Name $filter.displayName -Id $existingFilterNames[$filter.displayName] -Platform $filter.platform -Type 'DeviceFilter' -Action 'Skipped' -Status 'Already exists'
                    continue
                }

                # Add to list of filters to create
                $filtersToCreate += $filter
            }
        } catch {
            $errMessage = Get-GraphErrorMessage -ErrorRecord $_
            Write-HydrationLog -Message "  Failed to parse: $($templateFile.Name) - $errMessage" -Level Warning
            $results += New-HydrationResult -Name $templateFile.Name -Path $templateFile.FullName -Type 'DeviceFilter' -Action 'Failed' -Status "Parse error: $errMessage"
        }
    }

    # Handle WhatIf mode for creation
    if ($WhatIfPreference) {
        foreach ($filter in $filtersToCreate) {
            Write-HydrationLog -Message "  WouldCreate: $($filter.displayName)" -Level Info
            $results += New-HydrationResult -Name $filter.displayName -Platform $filter.platform -Type 'DeviceFilter' -Action 'WouldCreate' -Status 'DryRun'
        }
        return $results
    }

    # Batch create filters with retry logic
    if ($filtersToCreate.Count -gt 0) {
        $maxBatchSize = if ($script:MaxBatchSize) { $script:MaxBatchSize } else { 10 }
        $maxRetries = 3
        $retryDelaySeconds = 2
        Write-Verbose "Creating $($filtersToCreate.Count) device filters in batches..."

        for ($batchStart = 0; $batchStart -lt $filtersToCreate.Count; $batchStart += $maxBatchSize) {
            $batchEnd = [Math]::Min($batchStart + $maxBatchSize, $filtersToCreate.Count) - 1
            $currentBatch = $filtersToCreate[$batchStart..$batchEnd]

            # Track which items need retry
            $pendingItems = @($currentBatch)
            $retryCount = 0

            while ($pendingItems.Count -gt 0 -and $retryCount -le $maxRetries) {
                if ($retryCount -gt 0) {
                    $delay = $retryDelaySeconds * [Math]::Pow(2, $retryCount - 1)
                    Write-Verbose "Retrying $($pendingItems.Count) failed create(s) after ${delay}s delay (attempt $retryCount of $maxRetries)..."
                    Start-Sleep -Seconds $delay
                }

                $batchRequests = @()
                for ($i = 0; $i -lt $pendingItems.Count; $i++) {
                    $filter = $pendingItems[$i]

                    # Build description with hydration kit marker
                    $description = if ($filter.description) {
                        "$($filter.description) - Imported by Intune Hydration Kit"
                    } else {
                        "Imported by Intune Hydration Kit"
                    }

                    $filterBody = @{
                        displayName   = $filter.displayName
                        description   = $description
                        platform      = $filter.platform
                        rule          = $filter.rule
                        roleScopeTags = @("0")
                    }

                    $batchRequests += @{
                        id      = ($i + 1).ToString()
                        method  = "POST"
                        url     = "/deviceManagement/assignmentFilters"
                        headers = @{ "Content-Type" = "application/json" }
                        body    = $filterBody
                    }
                }

                $batchBody = @{ requests = $batchRequests }
                $itemsToRetry = @()

                try {
                    $batchResponse = Invoke-MgGraphRequest -Method POST -Uri "beta/`$batch" -Body $batchBody -ErrorAction Stop

                    foreach ($resp in $batchResponse.responses) {
                        $requestIndex = [int]$resp.id - 1
                        $filter = $pendingItems[$requestIndex]

                        if ($resp.status -eq 201) {
                            Write-HydrationLog -Message "  Created: $($filter.displayName)" -Level Info
                            $results += New-HydrationResult -Name $filter.displayName -Id $resp.body.id -Platform $filter.platform -Type 'DeviceFilter' -Action 'Created' -Status 'Success'
                        } elseif ($resp.status -eq 409) {
                            # Conflict - filter was created between check and creation (race condition)
                            Write-HydrationLog -Message "  Skipped: $($filter.displayName) (race condition)" -Level Info
                            $results += New-HydrationResult -Name $filter.displayName -Platform $filter.platform -Type 'DeviceFilter' -Action 'Skipped' -Status 'Already exists (race condition)'
                        } elseif ($resp.status -ge 500 -and $retryCount -lt $maxRetries) {
                            # Server error - queue for retry
                            Write-Verbose "Server error ($($resp.status)) for '$($filter.displayName)' - will retry"
                            $itemsToRetry += $filter
                        } else {
                            $errorMessage = if ($resp.body.error.message) { $resp.body.error.message } else { "HTTP $($resp.status)" }
                            Write-HydrationLog -Message "  [!] Failed: $($filter.displayName) - $errorMessage" -Level Warning
                            $results += New-HydrationResult -Name $filter.displayName -Platform $filter.platform -Type 'DeviceFilter' -Action 'Failed' -Status $errorMessage
                        }
                    }
                } catch {
                    if ($retryCount -lt $maxRetries) {
                        Write-Verbose "Batch create failed, will retry: $_"
                        $itemsToRetry = $pendingItems
                    } else {
                        Write-Warning "Batch create failed: $_"
                        foreach ($filter in $pendingItems) {
                            $results += New-HydrationResult -Name $filter.displayName -Platform $filter.platform -Type 'DeviceFilter' -Action 'Failed' -Status "Batch create failed: $_"
                        }
                    }
                }

                $pendingItems = $itemsToRetry
                $retryCount++
            }
        }
    }

    return $results
}
