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
                if ($existingFilter.displayName) {
                    $isTagged = Test-HydrationKitObject -Description $existingFilter.description
                    if (-not $existingFilters.ContainsKey($existingFilter.displayName)) {
                        $existingFilters[$existingFilter.displayName] = @{
                            Id          = $existingFilter.id
                            Description = $existingFilter.description
                            IsTagged    = $isTagged
                        }
                    } elseif ($isTagged -and -not $existingFilters[$existingFilter.displayName].IsTagged) {
                        $existingFilters[$existingFilter.displayName] = @{
                            Id          = $existingFilter.id
                            Description = $existingFilter.description
                            IsTagged    = $true
                        }
                    }
                }
            }
            $listUri = $existingFiltersResponse.'@odata.nextLink'
        } while ($listUri)
    } catch {
        Write-Warning "Could not retrieve existing filters: $_"
        $existingFilters = @{}
    }

    # Remove existing filters if requested
    # SAFETY: Only delete filters that have "Imported by Intune Hydration Kit" in description
    if ($RemoveExisting) {
        # Load template names to scope deletes to only filters this kit would create
        $knownTemplateNames = Get-TemplateDisplayNames -TemplateFiles $templateFiles -ArrayProperty 'filters'

        # Collect filters to delete (only those with hydration marker AND matching a template name)
        $filtersToDelete = @()
        foreach ($filterName in $existingFilters.Keys) {
            $filterInfo = $existingFilters[$filterName]

            $deleteDecision = Resolve-HydrationMarkedDeleteCandidate `
                -Name $filterName `
                -Description $filterInfo.Description `
                -KnownTemplateNames $knownTemplateNames `
                -FullObjectUri "beta/deviceManagement/assignmentFilters/$($filterInfo.Id)"
            if (-not $deleteDecision.IsMatch) {
                Write-Verbose "Skipping '$filterName' - $($deleteDecision.Message)"
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

        # Handle WhatIf/Confirm mode
        if (-not $PSCmdlet.ShouldProcess("$($filtersToDelete.Count) device filter(s)", "Delete")) {
            if ($WhatIfPreference) {
                foreach ($filter in $filtersToDelete) {
                    Write-HydrationLog -Message "  WouldDelete: $($filter.Name)" -Level Info
                    $results += New-HydrationResult -Name $filter.Name -Type 'DeviceFilter' -Action 'WouldDelete' -Status 'DryRun'
                }
            }
            return $results
        }

        # Batch delete filters using centralized helper
        $results += Invoke-GraphBatchOperation -Items $filtersToDelete -Operation 'DELETE' -BaseUrl '/deviceManagement/assignmentFilters' -ResultType 'DeviceFilter'

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

                # Compute canonical prefixed name
                $prefixedName = "$($script:ImportPrefix)$($filter.displayName)"

                # Dual lookup: check both prefixed and unprefixed (legacy) names
                $existingName = $null
                $existingEntry = $null
                if ($existingFilters.ContainsKey($prefixedName) -and $existingFilters[$prefixedName].IsTagged) {
                    $existingName = $prefixedName
                    $existingEntry = $existingFilters[$prefixedName]
                } elseif ($existingFilters.ContainsKey($filter.displayName) -and $existingFilters[$filter.displayName].IsTagged) {
                    $existingName = $filter.displayName
                    $existingEntry = $existingFilters[$filter.displayName]
                }

                if ($existingEntry) {
                    Write-HydrationLog -Message "  Skipped: $existingName" -Level Info
                    $results += New-HydrationResult -Name $existingName -Id $existingEntry.Id -Platform $filter.platform -Type 'DeviceFilter' -Action 'Skipped' -Status 'Already exists'
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

    # Handle WhatIf/Confirm mode for creation
    if (-not $PSCmdlet.ShouldProcess("$($filtersToCreate.Count) device filter(s)", "Create")) {
        if ($WhatIfPreference) {
            foreach ($filter in $filtersToCreate) {
                $prefixedName = if ($filter.displayName.StartsWith($script:ImportPrefix)) { $filter.displayName } else { "$($script:ImportPrefix)$($filter.displayName)" }
                Write-HydrationLog -Message "  WouldCreate: $prefixedName" -Level Info
                $results += New-HydrationResult -Name $prefixedName -Platform $filter.platform -Type 'DeviceFilter' -Action 'WouldCreate' -Status 'DryRun'
            }
        }
        return $results
    }

    # Batch create filters using centralized helper
    if ($filtersToCreate.Count -gt 0) {
        $batchItems = @()
        foreach ($filter in $filtersToCreate) {
            $prefixedName = if ($filter.displayName.StartsWith($script:ImportPrefix)) { $filter.displayName } else { "$($script:ImportPrefix)$($filter.displayName)" }
            $filterBody = @{
                displayName   = $prefixedName
                description   = New-HydrationDescription -ExistingText $filter.description
                platform      = $filter.platform
                rule          = $filter.rule
                roleScopeTags = @("0")
            }
            $batchItems += @{
                Name     = $prefixedName
                Platform = $filter.platform
                BodyJson = ($filterBody | ConvertTo-Json -Depth 10 -Compress)
            }
        }
        $results += Invoke-GraphBatchOperation -Items $batchItems -Operation 'POST' -BaseUrl '/deviceManagement/assignmentFilters' -ResultType 'DeviceFilter'
    }

    return $results
}
