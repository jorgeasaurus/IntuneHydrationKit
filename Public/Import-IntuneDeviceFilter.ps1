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
    .EXAMPLE
        Import-IntuneDeviceFilter
    .EXAMPLE
        Import-IntuneDeviceFilter -TemplatePath ./MyFilters
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [string]$TemplatePath,

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

    $templateFiles = Get-HydrationTemplates -Path $TemplatePath -Recurse -ResourceType "filter template"

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
                        Id = $existingFilter.id
                        Description = $existingFilter.description
                    }
                }
            }
            $listUri = $existingFiltersResponse.'@odata.nextLink'
        } while ($listUri)
    }
    catch {
        Write-Warning "Could not retrieve existing filters: $_"
        $existingFilters = @{}
    }

    # Build a simple name->id lookup for backwards compatibility in the import section
    $existingFilterNames = @{}
    foreach ($key in $existingFilters.Keys) {
        $existingFilterNames[$key] = $existingFilters[$key].Id
    }

    # Remove existing filters if requested
    # SAFETY: Only delete filters that have "Imported by Intune-Hydration-Kit" in description
    if ($RemoveExisting) {
        foreach ($filterName in $existingFilters.Keys) {
            $filterInfo = $existingFilters[$filterName]

            # Safety check: Only delete if created by this kit (has hydration marker in description)
            if (-not (Test-HydrationKitObject -Description $filterInfo.Description -ObjectName $filterName)) {
                Write-Verbose "Skipping '$filterName' - not created by Intune-Hydration-Kit"
                continue
            }

            if ($PSCmdlet.ShouldProcess($filterName, "Delete device filter")) {
                try {
                    Invoke-MgGraphRequest -Method DELETE -Uri "beta/deviceManagement/assignmentFilters/$($filterInfo.Id)" -ErrorAction Stop
                    Write-HydrationLog -Message "  Deleted: $filterName" -Level Info
                    $results += New-HydrationResult -Name $filterName -Type 'DeviceFilter' -Action 'Deleted' -Status 'Success'
                }
                catch {
                    $errMessage = Get-GraphErrorMessage -ErrorRecord $_
                    Write-HydrationLog -Message "  Failed: $filterName - $errMessage" -Level Warning
                    $results += New-HydrationResult -Name $filterName -Type 'DeviceFilter' -Action 'Failed' -Status "Delete failed: $errMessage"
                }
            }
            else {
                Write-HydrationLog -Message "  WouldDelete: $filterName" -Level Info
                $results += New-HydrationResult -Name $filterName -Type 'DeviceFilter' -Action 'WouldDelete' -Status 'DryRun'
            }
        }

        return $results
    }

    # Process each template file
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

                try {
                    # Check if filter already exists using pre-fetched list
                    if ($existingFilterNames.ContainsKey($filter.displayName)) {
                        Write-HydrationLog -Message "  Skipped: $($filter.displayName)" -Level Info
                        $results += New-HydrationResult -Name $filter.displayName -Id $existingFilterNames[$filter.displayName] -Platform $filter.platform -Type 'DeviceFilter' -Action 'Skipped' -Status 'Already exists'
                        continue
                    }

                    if ($PSCmdlet.ShouldProcess($filter.displayName, "Create device filter")) {
                        # Build description with hydration kit marker
                        $description = if ($filter.description) {
                            "$($filter.description) - Imported by Intune-Hydration-Kit"
                        } else {
                            "Imported by Intune-Hydration-Kit"
                        }

                        $filterBody = @{
                            displayName = $filter.displayName
                            description = $description
                            platform = $filter.platform
                            rule = $filter.rule
                            roleScopeTags = @("0")
                        }

                        $newFilter = Invoke-MgGraphRequest -Method POST -Uri "beta/deviceManagement/assignmentFilters" -Body $filterBody -ErrorAction Stop

                        Write-HydrationLog -Message "  Created: $($filter.displayName)" -Level Info

                        $results += New-HydrationResult -Name $filter.displayName -Id $newFilter.id -Platform $filter.platform -Type 'DeviceFilter' -Action 'Created' -Status 'Success'
                    }
                    else {
                        Write-HydrationLog -Message "  WouldCreate: $($filter.displayName)" -Level Info
                        $results += New-HydrationResult -Name $filter.displayName -Platform $filter.platform -Type 'DeviceFilter' -Action 'WouldCreate' -Status 'DryRun'
                    }
                }
                catch {
                    $errMessage = Get-GraphErrorMessage -ErrorRecord $_
                    Write-HydrationLog -Message "  Failed: $($filter.displayName) - $errMessage" -Level Warning
                    $results += New-HydrationResult -Name $filter.displayName -Platform $filter.platform -Type 'DeviceFilter' -Action 'Failed' -Status $errMessage
                }
            }
        }
        catch {
            $errMessage = Get-GraphErrorMessage -ErrorRecord $_
            Write-HydrationLog -Message "  Failed to parse: $($templateFile.Name) - $errMessage" -Level Warning
            $results += New-HydrationResult -Name $templateFile.Name -Path $templateFile.FullName -Type 'DeviceFilter' -Action 'Failed' -Status "Parse error: $errMessage"
        }
    }

    return $results
}
