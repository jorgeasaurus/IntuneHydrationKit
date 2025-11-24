function Import-IntuneAppProtectionPolicy {
    <#
    .SYNOPSIS
        Imports app protection (MAM) policies from templates
    .DESCRIPTION
        Reads app protection templates and upserts Android/iOS managed app protection policies via Graph.
    .PARAMETER TemplatePath
        Path to the app protection template directory (defaults to Templates/AppProtection)
    .EXAMPLE
        Import-IntuneAppProtectionPolicy
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [string]$TemplatePath,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$RemoveExisting,

        [Parameter()]
        [switch]$TestMode
    )

    if (-not $TemplatePath) {
        $TemplatePath = Join-Path -Path $script:TemplatesPath -ChildPath "AppProtection"
    }

    if (-not (Test-Path -Path $TemplatePath)) {
        Write-Warning "App protection template directory not found: $TemplatePath"
        return @()
    }

    $templateFiles = Get-ChildItem -Path $TemplatePath -Filter "*.json" -File -Recurse

    # Test mode - only process first template
    if ($TestMode -and $templateFiles.Count -gt 0) {
        $templateFiles = $templateFiles | Select-Object -First 1
        Write-Host "Test mode: Processing only first template: $($templateFiles.Name)" -InformationAction Continue
    }

    if (-not $templateFiles -or $templateFiles.Count -eq 0) {
        Write-Warning "No app protection templates found in: $TemplatePath"
        return @()
    }

    $typeToEndpoint = @{
        '#microsoft.graph.androidManagedAppProtection' = 'beta/deviceAppManagement/androidManagedAppProtections'
        '#microsoft.graph.iosManagedAppProtection'     = 'beta/deviceAppManagement/iosManagedAppProtections'
    }

    $results = @()

    # Remove existing app protection policies if requested - ONLY policies that match template names
    if ($RemoveExisting) {
        # Get template names to know what we manage
        $templateNames = @()
        foreach ($templateFile in $templateFiles) {
            $template = Get-Content -Path $templateFile.FullName -Raw | ConvertFrom-Json
            if ($template.displayName) {
                $templateNames += $template.displayName
            }
        }

        Write-Host "Removing managed app protection policies..." -InformationAction Continue

        foreach ($endpoint in $typeToEndpoint.Values) {
            $listUri = $endpoint
            do {
                try {
                    $existing = Invoke-MgGraphRequest -Method GET -Uri $listUri -ErrorAction Stop
                    foreach ($policy in $existing.value) {
                        $policyName = $policy.displayName
                        $policyId = $policy.id

                        # Only delete if it matches a template name
                        if ($policyName -notin $templateNames) {
                            continue
                        }

                        if ($PSCmdlet.ShouldProcess($policyName, "Delete app protection policy")) {
                            try {
                                Invoke-MgGraphRequest -Method DELETE -Uri "$endpoint/$policyId" -ErrorAction Stop
                                Write-Host "Deleted app protection policy: $policyName (ID: $policyId)" -InformationAction Continue
                                $results += New-HydrationResult -Name $policyName -Type 'AppProtection' -Action 'Deleted' -Status 'Success'
                            }
                            catch {
                                $errMessage = Get-GraphErrorMessage -ErrorRecord $_
                                Write-Warning "Failed to delete app protection policy '$policyName': $errMessage"
                                $results += New-HydrationResult -Name $policyName -Type 'AppProtection' -Action 'Failed' -Status "Delete failed: $errMessage"
                            }
                        }
                        else {
                            $results += New-HydrationResult -Name $policyName -Type 'AppProtection' -Action 'WouldDelete' -Status 'DryRun'
                        }
                    }
                    $listUri = $existing.'@odata.nextLink'
                }
                catch {
                    break
                }
            } while ($listUri)
        }

        # RemoveExisting mode - only delete, don't create
        $summary = Get-ResultSummary -Results $results
        Write-Host "App protection removal complete: $($summary.Deleted) deleted, $($summary.Failed) failed" -InformationAction Continue
        return $results
    }

    foreach ($templateFile in $templateFiles) {
        try {
            $template = Get-Content -Path $templateFile.FullName -Raw -Encoding utf8 | ConvertFrom-Json
            $displayName = $template.displayName
            $odataType = $template.'@odata.type'

            if (-not $displayName -or -not $odataType) {
                Write-Warning "Template missing displayName or @odata.type: $($templateFile.FullName)"
                $results += New-HydrationResult -Name $templateFile.Name -Path $templateFile.FullName -Type 'AppProtection' -Action 'Failed' -Status 'Missing displayName or @odata.type'
                continue
            }

            $endpoint = $typeToEndpoint[$odataType]
            if (-not $endpoint) {
                Write-Warning "Unsupported @odata.type '$odataType' in $($templateFile.FullName) - skipping"
                $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'AppProtection' -Action 'Skipped' -Status "Unsupported @odata.type: $odataType"
                continue
            }

            # Check for existing policy by display name with pagination
            $existingMatch = $null
            $listUri = $endpoint
            :paginationLoop do {
                $existing = Invoke-MgGraphRequest -Method GET -Uri $listUri -ErrorAction Stop
                $existingMatch = $existing.value | Where-Object { $_.displayName -eq $displayName }
                if ($existingMatch) {
                    break paginationLoop
                }
                $listUri = $existing.'@odata.nextLink'
            } while ($listUri)

            if ($existingMatch) {
                Write-Host "  Skipped: $displayName (already exists)" -InformationAction Continue
                $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'AppProtection' -Action 'Skipped' -Status 'Already exists'
                continue
            }

            # Prepare body (remove read-only properties)
            $importBody = [Management.Automation.PSSerializer]::Deserialize(
                [Management.Automation.PSSerializer]::Serialize($template)
            )
            $propsToRemove = @(
                'id',
                'createdDateTime',
                'lastModifiedDateTime',
                '@odata.context',
                'apps',
                'assignments',
                'targetedAppManagementLevels'
            )
            foreach ($prop in $propsToRemove) {
                if ($importBody.PSObject.Properties[$prop]) {
                    $importBody.PSObject.Properties.Remove($prop)
                }
            }

            # Add hydration kit tag to description
            $existingDesc = if ($importBody.description) { $importBody.description } else { "" }
            $importBody.description = if ($existingDesc) { "$existingDesc - Imported by Intune-Hydration-Kit" } else { "Imported by Intune-Hydration-Kit" }

            # Remove empty manufacturer/model allowlists
            if ($importBody.allowedAndroidDeviceManufacturers -eq "") {
                $importBody.PSObject.Properties.Remove('allowedAndroidDeviceManufacturers') | Out-Null
            }
            if ($importBody.allowedIosDeviceModels -eq "") {
                $importBody.PSObject.Properties.Remove('allowedIosDeviceModels') | Out-Null
            }

            if ($PSCmdlet.ShouldProcess($displayName, "Create app protection policy")) {
                $response = Invoke-MgGraphRequest -Method POST -Uri $endpoint -Body ($importBody | ConvertTo-Json -Depth 100) -ContentType 'application/json' -ErrorAction Stop
                Write-Host "  Created: $displayName" -InformationAction Continue
                $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'AppProtection' -Action 'Created' -Status 'Success'
            }
            else {
                $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'AppProtection' -Action 'WouldCreate' -Status 'DryRun'
            }
        }
        catch {
            $errMessage = Get-GraphErrorMessage -ErrorRecord $_
            Write-Warning "Failed to import app protection policy from $($templateFile.FullName): $errMessage"
            $results += New-HydrationResult -Name $templateFile.Name -Path $templateFile.FullName -Type 'AppProtection' -Action 'Failed' -Status $errMessage
        }
    }

    $summary = Get-ResultSummary -Results $results

    Write-Host "App protection import complete: $($summary.Created) created, $($summary.Skipped) skipped, $($summary.Failed) failed" -InformationAction Continue

    return $results
}
