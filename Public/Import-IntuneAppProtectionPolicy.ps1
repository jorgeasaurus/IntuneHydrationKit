function Import-IntuneAppProtectionPolicy {
    <#
    .SYNOPSIS
        Imports app protection (MAM) policies from templates
    .DESCRIPTION
        Reads app protection templates and upserts Android/iOS managed app protection policies via Graph.
    .PARAMETER TemplatePath
        Path to the app protection template directory (defaults to Templates/AppProtection)
    .PARAMETER Platform
        Filter templates by platform. Valid values: iOS, Android, All.
        Defaults to 'All' which imports all app protection templates regardless of platform.
        Note: App protection policies only apply to iOS and Android platforms.
    .EXAMPLE
        Import-IntuneAppProtectionPolicy
    .EXAMPLE
        Import-IntuneAppProtectionPolicy -Platform iOS
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [string]$TemplatePath,

        [Parameter()]
        [ValidateSet('iOS', 'Android', 'All')]
        [string[]]$Platform = @('All'),

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

    $templateFiles = Get-FilteredTemplates -Path $TemplatePath -Platform $Platform -FilterMode 'Suffix' -Recurse -ResourceType "app protection template"

    if (-not $templateFiles -or $templateFiles.Count -eq 0) {
        Write-Warning "No app protection templates found in: $TemplatePath"
        return @()
    }

    $typeToEndpoint = @{
        '#microsoft.graph.androidManagedAppProtection' = 'beta/deviceAppManagement/androidManagedAppProtections'
        '#microsoft.graph.iosManagedAppProtection'     = 'beta/deviceAppManagement/iosManagedAppProtections'
    }

    $results = @()

    # Prefetch existing policies from both endpoints
    # Note: App protection policies don't support $select for description, so we fetch all properties
    $existingPolicies = @{}
    foreach ($endpoint in $typeToEndpoint.Values) {
        try {
            $listUri = $endpoint
            do {
                $existing = Invoke-MgGraphRequest -Method GET -Uri $listUri -ErrorAction Stop
                foreach ($policy in $existing.value) {
                    if (-not $existingPolicies.ContainsKey($policy.displayName)) {
                        $existingPolicies[$policy.displayName] = @{
                            Id          = $policy.id
                            Description = $policy.description
                            Endpoint    = $endpoint
                        }
                    }
                }
                $listUri = $existing.'@odata.nextLink'
            } while ($listUri)
        } catch {
            Write-Warning "Could not retrieve existing policies from $endpoint`: $_"
        }
    }

    # Remove existing app protection policies if requested
    # SAFETY: Only delete policies that have "Imported by Intune Hydration Kit" in description
    if ($RemoveExisting) {
        # Group policies by endpoint for batch deletion
        $policiesByEndpoint = @{}
        foreach ($policyName in $existingPolicies.Keys) {
            $policyInfo = $existingPolicies[$policyName]

            if (-not (Test-HydrationKitObject -Description $policyInfo.Description -ObjectName $policyName)) {
                Write-Verbose "Skipping '$policyName' - not created by Intune Hydration Kit"
                continue
            }

            $relativePath = $policyInfo.Endpoint -replace '^beta/', ''
            if (-not $policiesByEndpoint.ContainsKey($relativePath)) {
                $policiesByEndpoint[$relativePath] = @()
            }
            $policiesByEndpoint[$relativePath] += @{
                Name = $policyName
                Id   = $policyInfo.Id
            }
        }

        $totalPolicies = ($policiesByEndpoint.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
        if ($totalPolicies -eq 0) {
            Write-Verbose "No app protection policies found to delete"
            return $results
        }

        if ($WhatIfPreference) {
            foreach ($endpoint in $policiesByEndpoint.Keys) {
                foreach ($policy in $policiesByEndpoint[$endpoint]) {
                    Write-HydrationLog -Message "  WouldDelete: $($policy.Name)" -Level Info
                    $results += New-HydrationResult -Name $policy.Name -Type 'AppProtection' -Action 'WouldDelete' -Status 'DryRun'
                }
            }
            return $results
        }

        foreach ($endpoint in $policiesByEndpoint.Keys) {
            $results += Invoke-GraphBatchOperation -Items $policiesByEndpoint[$endpoint] -Operation 'DELETE' -BaseUrl "/$endpoint" -ResultType 'AppProtection'
        }

        return $results
    }

    # Collect policies to create
    $policiesToCreate = @()
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

            # Check for existing policy using prefetched list
            if ($existingPolicies.ContainsKey($displayName)) {
                Write-HydrationLog -Message "  Skipped: $displayName" -Level Info
                $results += New-HydrationResult -Name $displayName -Id $existingPolicies[$displayName].Id -Path $templateFile.FullName -Type 'AppProtection' -Action 'Skipped' -Status 'Already exists'
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
            $importBody.description = if ($existingDesc) { "$existingDesc - Imported by Intune Hydration Kit" } else { "Imported by Intune Hydration Kit" }

            # Remove empty manufacturer/model allowlists
            if ($importBody.allowedAndroidDeviceManufacturers -eq "") {
                $importBody.PSObject.Properties.Remove('allowedAndroidDeviceManufacturers') | Out-Null
            }
            if ($importBody.allowedIosDeviceModels -eq "") {
                $importBody.PSObject.Properties.Remove('allowedIosDeviceModels') | Out-Null
            }

            # Store as JSON string to avoid serialization issues
            $policiesToCreate += @{
                Name     = $displayName
                Path     = $templateFile.FullName
                Endpoint = $endpoint
                BodyJson = ($importBody | ConvertTo-Json -Depth 100 -Compress)
            }
        } catch {
            $errMessage = Get-GraphErrorMessage -ErrorRecord $_
            Write-HydrationLog -Message "  Failed: $($templateFile.Name) - $errMessage" -Level Warning
            $results += New-HydrationResult -Name $templateFile.Name -Path $templateFile.FullName -Type 'AppProtection' -Action 'Failed' -Status $errMessage
        }
    }

    if ($WhatIfPreference) {
        foreach ($policy in $policiesToCreate) {
            Write-HydrationLog -Message "  WouldCreate: $($policy.Name)" -Level Info
            $results += New-HydrationResult -Name $policy.Name -Path $policy.Path -Type 'AppProtection' -Action 'WouldCreate' -Status 'DryRun'
        }
        return $results
    }

    if ($policiesToCreate.Count -gt 0) {
        # Group policies by endpoint for batch creation
        $policiesByEndpoint = @{}
        foreach ($policy in $policiesToCreate) {
            $relativePath = $policy.Endpoint -replace '^beta/', ''
            if (-not $policiesByEndpoint.ContainsKey($relativePath)) {
                $policiesByEndpoint[$relativePath] = @()
            }
            $policiesByEndpoint[$relativePath] += $policy
        }

        foreach ($endpoint in $policiesByEndpoint.Keys) {
            $results += Invoke-GraphBatchOperation -Items $policiesByEndpoint[$endpoint] -Operation 'POST' -BaseUrl "/$endpoint" -ResultType 'AppProtection'
        }
    }

    return $results
}
