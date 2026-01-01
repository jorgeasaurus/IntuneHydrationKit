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
        [switch]$RemoveExisting
    )

    if (-not $TemplatePath) {
        $TemplatePath = Join-Path -Path $script:TemplatesPath -ChildPath "AppProtection"
    }

    if (-not (Test-Path -Path $TemplatePath)) {
        Write-Warning "App protection template directory not found: $TemplatePath"
        return @()
    }

    $templateFiles = Get-HydrationTemplates -Path $TemplatePath -Recurse -ResourceType "app protection template"

    if (-not $templateFiles -or $templateFiles.Count -eq 0) {
        Write-Warning "No app protection templates found in: $TemplatePath"
        return @()
    }

    $typeToEndpoint = @{
        '#microsoft.graph.androidManagedAppProtection' = 'beta/deviceAppManagement/androidManagedAppProtections'
        '#microsoft.graph.iosManagedAppProtection'     = 'beta/deviceAppManagement/iosManagedAppProtections'
    }

    $results = @()

    # Remove existing app protection policies if requested
    # SAFETY: Only delete policies that have "Imported by Intune-Hydration-Kit" in description
    if ($RemoveExisting) {
        foreach ($endpoint in $typeToEndpoint.Values) {
            $listUri = $endpoint
            do {
                try {
                    $existing = Invoke-MgGraphRequest -Method GET -Uri $listUri -ErrorAction Stop
                    foreach ($policy in $existing.value) {
                        $policyName = $policy.displayName
                        $policyId = $policy.id

                        # Safety check: Only delete if created by this kit (has hydration marker in description)
                        if (-not (Test-HydrationKitObject -Description $policy.description -ObjectName $policyName)) {
                            Write-Verbose "Skipping '$policyName' - not created by Intune-Hydration-Kit"
                            continue
                        }

                        if ($PSCmdlet.ShouldProcess($policyName, "Delete app protection policy")) {
                            try {
                                Invoke-MgGraphRequest -Method DELETE -Uri "$endpoint/$policyId" -ErrorAction Stop
                                Write-HydrationLog -Message "  Deleted: $policyName" -Level Info
                                $results += New-HydrationResult -Name $policyName -Type 'AppProtection' -Action 'Deleted' -Status 'Success'
                            }
                            catch {
                                $errMessage = Get-GraphErrorMessage -ErrorRecord $_
                                Write-HydrationLog -Message "  Failed: $policyName - $errMessage" -Level Warning
                                $results += New-HydrationResult -Name $policyName -Type 'AppProtection' -Action 'Failed' -Status "Delete failed: $errMessage"
                            }
                        }
                        else {
                            Write-HydrationLog -Message "  WouldDelete: $policyName" -Level Info
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
                Write-HydrationLog -Message "  Skipped: $displayName" -Level Info
                $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'AppProtection' -Action 'Skipped' -Status 'Already exists'
                continue
            }

            # Prepare body (remove read-only properties)
            $importBody = Copy-DeepObject -InputObject $template
            Remove-ReadOnlyGraphProperties -InputObject $importBody -AdditionalProperties @(
                'apps',
                'assignments',
                'targetedAppManagementLevels'
            )

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
                $null = Invoke-MgGraphRequest -Method POST -Uri $endpoint -Body ($importBody | ConvertTo-Json -Depth 100) -ContentType 'application/json' -ErrorAction Stop
                Write-HydrationLog -Message "  Created: $displayName" -Level Info
                $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'AppProtection' -Action 'Created' -Status 'Success'
            }
            else {
                Write-HydrationLog -Message "  WouldCreate: $displayName" -Level Info
                $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'AppProtection' -Action 'WouldCreate' -Status 'DryRun'
            }
        }
        catch {
            $errMessage = Get-GraphErrorMessage -ErrorRecord $_
            Write-HydrationLog -Message "  Failed: $($templateFile.Name) - $errMessage" -Level Warning
            $results += New-HydrationResult -Name $templateFile.Name -Path $templateFile.FullName -Type 'AppProtection' -Action 'Failed' -Status $errMessage
        }
    }

    return $results
}
