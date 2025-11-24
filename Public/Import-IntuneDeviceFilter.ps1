function Import-IntuneDeviceFilter {
    <#
    .SYNOPSIS
        Creates device filters for Intune
    .DESCRIPTION
        Creates device filters by manufacturer for each device OS platform (Windows, macOS, iOS/iPadOS, Android).
        Creates 3 manufacturer filters per OS: Dell/HP/Lenovo for Windows, Apple for macOS/iOS.
    .EXAMPLE
        Import-IntuneDeviceFilter
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$RemoveExisting,

        [Parameter()]
        [switch]$TestMode
    )

    $results = @()

    # Get all existing filters first with pagination (OData filter on displayName not supported for this endpoint)
    # Use $select to reduce payload size
    $existingFilterNames = @{}
    try {
        $listUri = "beta/deviceManagement/assignmentFilters?`$select=id,displayName"
        do {
            $existingFiltersResponse = Invoke-MgGraphRequest -Method GET -Uri $listUri -ErrorAction Stop
            foreach ($existingFilter in $existingFiltersResponse.value) {
                if (-not $existingFilterNames.ContainsKey($existingFilter.displayName)) {
                    $existingFilterNames[$existingFilter.displayName] = $existingFilter.id
                }
            }
            $listUri = $existingFiltersResponse.'@odata.nextLink'
        } while ($listUri)
    }
    catch {
        Write-Warning "Could not retrieve existing filters: $_"
        $existingFilterNames = @{}
    }

    # Define filters first so we know what to delete
    $filterDefinitions = @(
        # Windows filters by manufacturer
        @{
            DisplayName = "Windows - Dell Devices"
            Description = "Filter for Dell Windows devices"
            Platform = "windows10AndLater"
            Rule = '(device.manufacturer -eq "Dell Inc.")'
        },
        @{
            DisplayName = "Windows - HP Devices"
            Description = "Filter for HP Windows devices"
            Platform = "windows10AndLater"
            Rule = '(device.manufacturer -eq "HP") or (device.manufacturer -eq "Hewlett-Packard")'
        },
        @{
            DisplayName = "Windows - Lenovo Devices"
            Description = "Filter for Lenovo Windows devices"
            Platform = "windows10AndLater"
            Rule = '(device.manufacturer -eq "LENOVO")'
        },
        # macOS filters
        @{
            DisplayName = "macOS - Apple Devices"
            Description = "Filter for Apple macOS devices"
            Platform = "macOS"
            Rule = '(device.manufacturer -eq "Apple")'
        },
        @{
            DisplayName = "macOS - MacBook Devices"
            Description = "Filter for MacBook devices"
            Platform = "macOS"
            Rule = '(device.model -startsWith "MacBook")'
        },
        @{
            DisplayName = "macOS - iMac Devices"
            Description = "Filter for iMac devices"
            Platform = "macOS"
            Rule = '(device.model -startsWith "iMac")'
        },
        # iOS/iPadOS filters
        @{
            DisplayName = "iOS - iPhone Devices"
            Description = "Filter for iPhone devices"
            Platform = "iOS"
            Rule = '(device.model -startsWith "iPhone")'
        },
        @{
            DisplayName = "iOS - iPad Devices"
            Description = "Filter for iPad devices"
            Platform = "iOS"
            Rule = '(device.model -startsWith "iPad")'
        },
        @{
            DisplayName = "iOS - Corporate Owned"
            Description = "Filter for corporate-owned iOS/iPadOS devices"
            Platform = "iOS"
            Rule = '(device.deviceOwnership -eq "Corporate")'
        },
        # Android filters
        @{
            DisplayName = "Android - Samsung Devices"
            Description = "Filter for Samsung Android devices"
            Platform = "androidForWork"
            Rule = '(device.manufacturer -eq "samsung")'
        },
        @{
            DisplayName = "Android - Google Pixel Devices"
            Description = "Filter for Google Pixel devices"
            Platform = "androidForWork"
            Rule = '(device.manufacturer -eq "Google")'
        },
        @{
            DisplayName = "Android - Corporate Owned"
            Description = "Filter for corporate-owned Android devices"
            Platform = "androidForWork"
            Rule = '(device.deviceOwnership -eq "Corporate")'
        }
    )

    # Get the names of filters we manage
    $managedFilterNames = $filterDefinitions | ForEach-Object { $_.DisplayName }

    # Apply test mode - only process first filter
    if ($TestMode -and $filterDefinitions.Count -gt 0) {
        $filterDefinitions = @($filterDefinitions[0])
        Write-Host "Test mode: Processing only first filter: $($filterDefinitions[0].DisplayName)" -InformationAction Continue
    }

    # Remove existing filters if requested - ONLY filters defined in this codebase
    if ($RemoveExisting) {
        $filtersToDelete = $existingFilterNames.Keys | Where-Object { $_ -in $managedFilterNames }

        if ($filtersToDelete.Count -gt 0) {
            Write-Host "Removing $($filtersToDelete.Count) managed device filters..." -InformationAction Continue

            foreach ($filterName in $filtersToDelete) {
                $filterId = $existingFilterNames[$filterName]

                if ($PSCmdlet.ShouldProcess($filterName, "Delete device filter")) {
                    try {
                        Invoke-MgGraphRequest -Method DELETE -Uri "beta/deviceManagement/assignmentFilters/$filterId" -ErrorAction Stop
                        Write-Host "Deleted device filter: $filterName (ID: $filterId)" -InformationAction Continue
                        $results += New-HydrationResult -Name $filterName -Type 'DeviceFilter' -Action 'Deleted' -Status 'Success'
                    }
                    catch {
                        $errMessage = Get-GraphErrorMessage -ErrorRecord $_
                        Write-Warning "Failed to delete device filter '$filterName': $errMessage"
                        $results += New-HydrationResult -Name $filterName -Type 'DeviceFilter' -Action 'Failed' -Status "Delete failed: $errMessage"
                    }
                }
                else {
                    $results += New-HydrationResult -Name $filterName -Type 'DeviceFilter' -Action 'WouldDelete' -Status 'DryRun'
                }
            }
        }
        else {
            Write-Host "No managed device filters found to delete" -InformationAction Continue
        }

        # RemoveExisting mode - only delete, don't create
        $summary = Get-ResultSummary -Results $results
        Write-Host "Device filter removal complete: $($summary.Deleted) deleted, $($summary.Failed) failed" -InformationAction Continue
        return $results
    }

    foreach ($filter in $filterDefinitions) {
        try {
            # Check if filter already exists using pre-fetched list
            if ($existingFilterNames.ContainsKey($filter.DisplayName)) {
                Write-Host "  Skipped: $($filter.DisplayName) (already exists)" -InformationAction Continue
                $results += New-HydrationResult -Name $filter.DisplayName -Id $existingFilterNames[$filter.DisplayName] -Platform $filter.Platform -Action 'Skipped' -Status 'Already exists'
                continue
            }

            if ($PSCmdlet.ShouldProcess($filter.DisplayName, "Create device filter")) {
                $filterBody = @{
                    displayName = $filter.DisplayName
                    description = "$($filter.Description) - Imported by Intune-Hydration-Kit"
                    platform = $filter.Platform
                    rule = $filter.Rule
                    roleScopeTags = @("0")
                }

                $newFilter = Invoke-MgGraphRequest -Method POST -Uri "beta/deviceManagement/assignmentFilters" -Body $filterBody -ErrorAction Stop

                Write-Host "  Created: $($filter.DisplayName)" -InformationAction Continue

                $results += New-HydrationResult -Name $filter.DisplayName -Id $newFilter.id -Platform $filter.Platform -Action 'Created' -Status 'Success'
            }
            else {
                $results += New-HydrationResult -Name $filter.DisplayName -Platform $filter.Platform -Action 'WouldCreate' -Status 'DryRun'
            }
        }
        catch {
            Write-Warning "  Failed: $($filter.DisplayName) - $_"
            $results += New-HydrationResult -Name $filter.DisplayName -Platform $filter.Platform -Action 'Failed' -Status $_.Exception.Message
        }
    }

    # Summary
    $summary = Get-ResultSummary -Results $results

    Write-Host "Device filter import complete: $($summary.Created) created, $($summary.Skipped) skipped, $($summary.Failed) failed" -InformationAction Continue

    return $results
}
