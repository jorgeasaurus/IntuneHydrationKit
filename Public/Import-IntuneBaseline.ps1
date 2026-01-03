function Import-IntuneBaseline {
    <#
    .SYNOPSIS
        Imports OpenIntuneBaseline policies using IntuneManagement module
    .DESCRIPTION
        Downloads OpenIntuneBaseline from GitHub and imports all policies using the IntuneManagement module.
        Uses IntuneManagement's silent batch mode for automated imports.
    .PARAMETER BaselinePath
        Path to the OpenIntuneBaseline directory (will download if not specified)
    .PARAMETER IntuneManagementPath
        Path to IntuneManagement module (will download if not specified)
    .PARAMETER TenantId
        Target tenant ID (uses connected tenant if not specified)
    .PARAMETER ImportMode
        Import mode: SkipIfExists (default - skip policies that already exist)
    .PARAMETER IncludeAssignments
        Include policy assignments during import
    .EXAMPLE
        Import-IntuneBaseline
    .EXAMPLE
        Import-IntuneBaseline -BaselinePath ./OpenIntuneBaseline -ImportMode SkipIfExists
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [string]$BaselinePath,

        [Parameter()]
        [string]$TenantId,

        [Parameter()]
        [ValidateSet('SkipIfExists')]
        [string]$ImportMode = 'SkipIfExists',

        [Parameter()]
        [switch]$RemoveExisting
    )

    # Use connected tenant if not specified
    if (-not $TenantId -and $script:HydrationState.TenantId) {
        $TenantId = $script:HydrationState.TenantId
    }

    if (-not $TenantId) {
        throw "TenantId is required. Either connect using Connect-IntuneHydration or specify -TenantId parameter."
    }

    # Download OpenIntuneBaseline if not provided
    if (-not $BaselinePath -or -not (Test-Path -Path $BaselinePath)) {
        $BaselinePath = Get-OpenIntuneBaseline
    }

    # OpenIntuneBaseline uses OS-based folder structure:
    # - OS/IntuneManagement/ - Exported by IntuneManagement tool (requires Windows GUI to import)
    # - OS/NativeImport/ - Settings Catalog policies that can be imported via Graph API
    # - BYOD/AppProtection/ - App protection policies

    # Map folder names to Graph API endpoints
    $endpointMap = @{
        'NativeImport'                      = 'deviceManagement/configurationPolicies'
        'AppProtection'                     = 'deviceAppManagement/managedAppPolicies'
        'Administrative Templates'           = 'deviceManagement/groupPolicyConfigurations'
        'Compliance'                        = 'deviceManagement/deviceCompliancePolicies'
        'Compliance Policies'               = 'deviceManagement/deviceCompliancePolicies'
        'Configuration Profiles'            = 'deviceManagement/deviceConfigurations'
        'Device Configuration'              = 'deviceManagement/deviceConfigurations'
        'Device Enrollment Configurations'  = 'deviceManagement/deviceEnrollmentConfigurations'
        'Endpoint Security'                 = 'deviceManagement/intents'
        'Settings Catalog'                  = 'deviceManagement/configurationPolicies'
        'Scripts'                           = 'deviceManagement/deviceManagementScripts'
        'Proactive Remediations'            = 'deviceManagement/deviceHealthScripts'
        'Windows Autopilot'                 = 'deviceManagement/windowsAutopilotDeploymentProfiles'
        'App Configuration'                 = 'deviceAppManagement/mobileAppConfigurations'
        'App Protection'                    = 'deviceAppManagement/managedAppPolicies'
        'App Protection Policies'           = 'deviceAppManagement/managedAppPolicies'
    }

    # Map @odata.type to Graph API endpoints for IntuneManagement exports
    $odataTypeToEndpoint = @{
        # Device Configurations
        '#microsoft.graph.windowsHealthMonitoringConfiguration' = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.windows10GeneralConfiguration' = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.windows10EndpointProtectionConfiguration' = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.windows10CustomConfiguration' = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.windowsDeliveryOptimizationConfiguration' = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.windowsUpdateForBusinessConfiguration' = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.windowsIdentityProtectionConfiguration' = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.windowsKioskConfiguration' = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.editionUpgradeConfiguration' = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.sharedPCConfiguration' = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.windowsWifiConfiguration' = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.windowsWiredNetworkConfiguration' = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.macOSGeneralDeviceConfiguration' = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.macOSCustomConfiguration' = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.macOSEndpointProtectionConfiguration' = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.iosGeneralDeviceConfiguration' = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.iosCustomConfiguration' = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.androidGeneralDeviceConfiguration' = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.androidWorkProfileGeneralDeviceConfiguration' = 'deviceManagement/deviceConfigurations'
        # Compliance Policies
        '#microsoft.graph.windows10CompliancePolicy' = 'deviceManagement/deviceCompliancePolicies'
        '#microsoft.graph.windows81CompliancePolicy' = 'deviceManagement/deviceCompliancePolicies'
        '#microsoft.graph.macOSCompliancePolicy' = 'deviceManagement/deviceCompliancePolicies'
        '#microsoft.graph.iosCompliancePolicy' = 'deviceManagement/deviceCompliancePolicies'
        '#microsoft.graph.androidCompliancePolicy' = 'deviceManagement/deviceCompliancePolicies'
        '#microsoft.graph.androidWorkProfileCompliancePolicy' = 'deviceManagement/deviceCompliancePolicies'
        '#microsoft.graph.androidDeviceOwnerCompliancePolicy' = 'deviceManagement/deviceCompliancePolicies'
        # Settings Catalog / Configuration Policies
        '#microsoft.graph.deviceManagementConfigurationPolicy' = 'deviceManagement/configurationPolicies'
        # Windows Update for Business - Driver Updates
        '#microsoft.graph.windowsDriverUpdateProfile' = 'deviceManagement/windowsDriverUpdateProfiles'
    }

    # Folders that previously required IntuneManagement tool - now we try to import via Graph API
    $intuneManagementFolders = @('IntuneManagement')

    $results = @()

    # Check Windows Driver Update license upfront (cached for all driver update profiles)
    $hasDriverUpdateLicense = $null  # Lazy-loaded when needed

    # Remove existing baseline policies if requested
    # SAFETY: Only delete policies that have "Imported by Intune-Hydration-Kit" in description
    if ($RemoveExisting) {
        # Delete from main endpoints used by baselines
        $deleteEndpoints = @(
            'beta/deviceManagement/configurationPolicies',
            'beta/deviceManagement/deviceConfigurations',
            'beta/deviceManagement/deviceCompliancePolicies',
            'beta/deviceAppManagement/androidManagedAppProtections',
            'beta/deviceAppManagement/iosManagedAppProtections'
        )

        foreach ($endpoint in $deleteEndpoints) {
            try {
                $listUri = $endpoint
                do {
                    $existing = Invoke-MgGraphRequest -Method GET -Uri $listUri -ErrorAction Stop
                    foreach ($policy in $existing.value) {
                        $policyName = if ($policy.displayName) { $policy.displayName } elseif ($policy.name) { $policy.name } else { "Unknown" }
                        $policyId = $policy.id

                        # Safety check: Only delete if created by this kit (has hydration marker in description)
                        if (-not (Test-HydrationKitObject -Description $policy.description -ObjectName $policyName)) {
                            Write-Verbose "Skipping '$policyName' - not created by Intune-Hydration-Kit"
                            continue
                        }

                        if ($PSCmdlet.ShouldProcess($policyName, "Delete baseline policy")) {
                            try {
                                Invoke-MgGraphRequest -Method DELETE -Uri "$endpoint/$policyId" -ErrorAction Stop
                                Write-HydrationLog -Message "  Deleted: $policyName" -Level Info
                                $results += New-HydrationResult -Name $policyName -Type 'BaselinePolicy' -Action 'Deleted' -Status 'Success'
                            }
                            catch {
                                $errMessage = Get-GraphErrorMessage -ErrorRecord $_
                                Write-HydrationLog -Message "  Failed: $policyName - $errMessage" -Level Warning
                                $results += New-HydrationResult -Name $policyName -Type 'BaselinePolicy' -Action 'Failed' -Status "Delete failed: $errMessage"
                            }
                        }
                        else {
                            Write-HydrationLog -Message "  WouldDelete: $policyName" -Level Info
                            $results += New-HydrationResult -Name $policyName -Type 'BaselinePolicy' -Action 'WouldDelete' -Status 'DryRun'
                        }
                    }
                    $listUri = $existing.'@odata.nextLink'
                } while ($listUri)
            }
            catch {
                Write-Warning "Failed to process endpoint $endpoint : $_"
            }
        }

        return $results
    }

    # Find all policy type subfolders within OS folders (WINDOWS, MACOS, BYOD, WINDOWS365)
    # OpenIntuneBaseline structure: OS/PolicyType/policy.json
    $osFolders = Get-ChildItem -Path $BaselinePath -Directory | Where-Object {
        $_.Name -notmatch '^\.'
    }

    $totalPolicies = 0
    $policyTypefolders = @()

    foreach ($osFolder in $osFolders) {
        # Get policy type subfolders within each OS folder
        $subFolders = Get-ChildItem -Path $osFolder.FullName -Directory | Where-Object {
            $_.Name -notmatch '^\.' -and (Get-ChildItem -Path $_.FullName -Filter "*.json" -File -Recurse).Count -gt 0
        }

        foreach ($subFolder in $subFolders) {
            $jsonFiles = Get-ChildItem -Path $subFolder.FullName -Filter "*.json" -File -Recurse
            $totalPolicies += $jsonFiles.Count
            $policyTypefolders += @{
                Folder = $subFolder
                OsFolder = $osFolder.Name
                PolicyType = $subFolder.Name
            }
        }
    }

    if ($PSCmdlet.ShouldProcess("$totalPolicies policies from OpenIntuneBaseline", "Import to Intune")) {

        # Pre-fetch existing policies from all unique endpoints to avoid repeated API calls
        $endpointPolicyCache = @{}
        $uniqueEndpoints = $odataTypeToEndpoint.Values | Sort-Object -Unique
        foreach ($cacheEndpoint in $uniqueEndpoints) {
            $endpointPolicyCache[$cacheEndpoint] = @{}
            try {
                $listUri = "beta/$cacheEndpoint"
                do {
                    $cacheResponse = Invoke-MgGraphRequest -Method GET -Uri $listUri -ErrorAction Stop
                    foreach ($policy in $cacheResponse.value) {
                        # Use 'name' for configurationPolicies, 'displayName' for others
                        $policyDisplayName = if ($cacheEndpoint -eq 'deviceManagement/configurationPolicies') {
                            $policy.name
                        } else {
                            if ($policy.displayName) { $policy.displayName } elseif ($policy.name) { $policy.name } else { $null }
                        }
                        if ($policyDisplayName -and -not $endpointPolicyCache[$cacheEndpoint].ContainsKey($policyDisplayName)) {
                            $endpointPolicyCache[$cacheEndpoint][$policyDisplayName] = $policy.id
                        }
                    }
                    $listUri = $cacheResponse.'@odata.nextLink'
                } while ($listUri)
            }
            catch {
                # Endpoint might not support listing, continue without cache for this endpoint
                Write-Verbose "Could not cache policies from $cacheEndpoint - will check individually"
            }
        }

        foreach ($policyFolder in $policyTypefolders) {
            $folder = $policyFolder.Folder
            $folderName = $policyFolder.PolicyType
            $osName = $policyFolder.OsFolder
            $jsonFiles = Get-ChildItem -Path $folder.FullName -Filter "*.json" -File -Recurse

            # For IntuneManagement folders, try to import using @odata.type routing
            if ($folderName -in $intuneManagementFolders) {
                foreach ($jsonFile in $jsonFiles) {
                    $policyName = [System.IO.Path]::GetFileNameWithoutExtension($jsonFile.Name)

                    try {
                        # Read JSON content and replace %OrganizationId% placeholder with actual tenant ID
                        $jsonContent = Get-Content -Path $jsonFile.FullName -Raw
                        if ($jsonContent -match '%OrganizationId%') {
                            Write-Verbose "Replacing %OrganizationId% with tenant ID in $policyName"
                            $jsonContent = $jsonContent -replace '%OrganizationId%', $TenantId
                        }
                        $policyContent = $jsonContent | ConvertFrom-Json
                        $odataType = $policyContent.'@odata.type'

                        # Determine endpoint from @odata.type
                        $typeEndpoint = $odataTypeToEndpoint[$odataType]
                        if (-not $typeEndpoint) {
                            Write-Warning "  Skipping $policyName - unsupported @odata.type: $odataType"
                            $results += New-HydrationResult -Name $policyName -Path $jsonFile.FullName -Type "$osName/$folderName" -Action 'Skipped' -Status "Unsupported @odata.type: $odataType"
                            continue
                        }

                        # Check for Windows Driver Update license requirement
                        if ($typeEndpoint -eq 'deviceManagement/windowsDriverUpdateProfiles') {
                            # Lazy-load the license check (only check once)
                            if ($null -eq $hasDriverUpdateLicense) {
                                Write-Verbose "Checking Windows Driver Update license..."
                                $hasDriverUpdateLicense = Test-WindowsDriverUpdateLicense
                                if (-not $hasDriverUpdateLicense) {
                                    Write-HydrationLog -Message "Windows Driver Update profiles require additional licensing (Windows E3/E5, M365 Business Premium, etc.)" -Level Warning
                                }
                            }

                            if (-not $hasDriverUpdateLicense) {
                                Write-HydrationLog -Message "  Skipped: $policyName - Missing Windows Driver Update license" -Level Warning
                                $results += New-HydrationResult -Name $policyName -Path $jsonFile.FullName -Type "$osName/$folderName" -Action 'Skipped' -Status 'Missing Windows Driver Update license (requires Windows E3/E5, M365 Business Premium, or equivalent)'
                                continue
                            }
                        }

                        # Get display name
                        $displayName = $policyContent.displayName
                        if (-not $displayName) {
                            $displayName = $policyName
                        }

                        # Check if policy exists using pre-fetched cache
                        $existingPolicy = $endpointPolicyCache[$typeEndpoint].ContainsKey($displayName)

                        if ($existingPolicy -and $ImportMode -eq 'SkipIfExists') {
                            Write-HydrationLog -Message "  Skipped: $displayName" -Level Info
                            $results += New-HydrationResult -Name $displayName -Path $jsonFile.FullName -Type "$osName/$folderName" -Action 'Skipped' -Status 'Already exists'
                            continue
                        }

                        # Prepare import body - remove read-only and assignment properties
                        $importBody = Copy-DeepObject -InputObject $policyContent
                        Remove-ReadOnlyGraphProperties -InputObject $importBody -AdditionalProperties @(
                            'supportsScopeTags', 'deviceManagementApplicabilityRuleOsEdition',
                            'deviceManagementApplicabilityRuleOsVersion',
                            'deviceManagementApplicabilityRuleDeviceMode',
                            '@odata.id', '@odata.editLink',
                            'creationSource', 'settingCount', 'priorityMetaData',
                            'assignments', 'settingDefinitions', 'isAssigned'
                        )

                        # Add hydration kit tag to description
                        $existingDesc = if ($importBody.description) { $importBody.description } else { "" }
                        $importBody.description = if ($existingDesc) { "$existingDesc - Imported by Intune-Hydration-Kit" } else { "Imported by Intune-Hydration-Kit" }

                        # Remove properties with @odata annotations (metadata) except @odata.type
                        # Also remove #microsoft.graph.* action properties
                        $metadataProps = @($importBody.PSObject.Properties | Where-Object {
                            ($_.Name -match '^@odata\.' -and $_.Name -ne '@odata.type') -or
                            ($_.Name -match '@odata\.') -or
                            ($_.Name -match '^#microsoft\.graph\.')
                        })
                        foreach ($prop in $metadataProps) {
                            if ($prop.Name -ne '@odata.type') {
                                $importBody.PSObject.Properties.Remove($prop.Name)
                            }
                        }

                        # Special handling for Settings Catalog (configurationPolicies)
                        if ($typeEndpoint -eq 'deviceManagement/configurationPolicies') {
                            Write-Verbose "  Processing Settings Catalog policy: $displayName"
                            Write-Verbose "  Original properties: $($importBody.PSObject.Properties.Name -join ', ')"

                            # Build a clean body with only the required properties
                            $cleanBody = @{
                                name = $importBody.name
                                description = $importBody.description
                                platforms = $importBody.platforms
                                technologies = $importBody.technologies
                                settings = @()
                            }

                            Write-Verbose "  Building clean body with: name, description, platforms, technologies"

                            # Add optional properties if present
                            if ($importBody.roleScopeTagIds) {
                                $cleanBody.roleScopeTagIds = $importBody.roleScopeTagIds
                                Write-Verbose "  Added roleScopeTagIds"
                            }
                            if ($importBody.templateReference -and $importBody.templateReference.templateId) {
                                $cleanBody.templateReference = @{
                                    templateId = $importBody.templateReference.templateId
                                }
                                Write-Verbose "  Added templateReference with templateId: $($importBody.templateReference.templateId)"
                            }

                            # Clean settings - remove id and odata navigation properties from each setting
                            if ($importBody.settings) {
                                Write-Verbose "  Processing $($importBody.settings.Count) settings"
                                $settingIndex = 0
                                foreach ($setting in $importBody.settings) {
                                    $settingJson = $setting | ConvertTo-Json -Depth 100 -Compress
                                    $cleanSetting = $settingJson | ConvertFrom-Json

                                    # Remove 'id' and odata navigation link properties from the setting
                                    $propsToRemoveFromSetting = @($cleanSetting.PSObject.Properties | Where-Object {
                                        $_.Name -eq 'id' -or
                                        $_.Name -match '@odata\.' -or
                                        $_.Name -match 'settingDefinitions'
                                    })

                                    if ($propsToRemoveFromSetting.Count -gt 0) {
                                        Write-Verbose "  Setting[$settingIndex] - Removing properties: $($propsToRemoveFromSetting.Name -join ', ')"
                                    }

                                    foreach ($prop in $propsToRemoveFromSetting) {
                                        $cleanSetting.PSObject.Properties.Remove($prop.Name)
                                    }

                                    $cleanBody.settings += $cleanSetting
                                    $settingIndex++
                                }
                            }

                            $importBody = [PSCustomObject]$cleanBody

                            # Debug: Show final body properties
                            Write-Verbose "  Final body properties: $($importBody.PSObject.Properties.Name -join ', ')"

                            # Debug: Show first 500 chars of JSON being sent
                            $debugJson = $importBody | ConvertTo-Json -Depth 100 -Compress
                            Write-Verbose "  Request body preview (first 500 chars): $($debugJson.Substring(0, [Math]::Min(500, $debugJson.Length)))"
                        }

                        # Clean up scheduledActionsForRule - remove nested @odata.context and IDs
                        if ($importBody.scheduledActionsForRule) {
                            $cleanedActions = @()
                            foreach ($action in $importBody.scheduledActionsForRule) {
                                $cleanAction = @{
                                    ruleName = $action.ruleName
                                }
                                if ($action.scheduledActionConfigurations) {
                                    $cleanConfigs = @()
                                    foreach ($config in $action.scheduledActionConfigurations) {
                                        # Ensure notificationMessageCCList is always an array, never null
                                        $ccList = @()
                                        if ($null -ne $config.notificationMessageCCList -and $config.notificationMessageCCList.Count -gt 0) {
                                            $ccList = @($config.notificationMessageCCList)
                                        }
                                        $cleanConfig = @{
                                            actionType = $config.actionType
                                            gracePeriodHours = [int]$config.gracePeriodHours
                                            notificationTemplateId = if ($config.notificationTemplateId) { $config.notificationTemplateId } else { "" }
                                            notificationMessageCCList = $ccList
                                        }
                                        $cleanConfigs += $cleanConfig
                                    }
                                    $cleanAction.scheduledActionConfigurations = $cleanConfigs
                                }
                                $cleanedActions += $cleanAction
                            }
                            $importBody.scheduledActionsForRule = $cleanedActions
                        }

                        # Create the policy
                        $null = Invoke-MgGraphRequest -Method POST -Uri "beta/$typeEndpoint" -Body ($importBody | ConvertTo-Json -Depth 100) -ContentType 'application/json' -ErrorAction Stop

                        Write-HydrationLog -Message "  Created: $displayName" -Level Info
                        $results += New-HydrationResult -Name $displayName -Path $jsonFile.FullName -Type "$osName/$folderName" -Action 'Created' -Status 'Success'
                    }
                    catch {
                        $errorMsg = Get-GraphErrorMessage -ErrorRecord $_
                        Write-HydrationLog -Message "  Failed: $policyName - $errorMsg" -Level Warning
                        $results += New-HydrationResult -Name $policyName -Path $jsonFile.FullName -Type "$osName/$folderName" -Action 'Failed' -Status $errorMsg
                    }

                    Start-Sleep -Milliseconds 100
                }
                continue
            }

            # Determine API endpoint based on policy type folder name
            $endpoint = $endpointMap[$folderName]
            if (-not $endpoint) {
                Write-Warning "No endpoint mapping for folder: $osName/$folderName - skipping"
                foreach ($jsonFile in $jsonFiles) {
                    $policyName = [System.IO.Path]::GetFileNameWithoutExtension($jsonFile.Name)
                    $results += New-HydrationResult -Name $policyName -Path $jsonFile.FullName -Type "$osName/$folderName" -Action 'Skipped' -Status "No endpoint mapping for $folderName"
                }
                continue
            }

            # Progress tracking for this folder
            $folderTotal = $jsonFiles.Count
            $folderCurrent = 0

            # Pre-fetch existing policies for this endpoint to avoid repeated API calls (page through all results)
            $existingPolicies = @{}
            try {
                $listUri = "beta/$endpoint"
                do {
                    $existingResponse = Invoke-MgGraphRequest -Method GET -Uri $listUri -ErrorAction Stop
                    foreach ($policy in $existingResponse.value) {
                        $policyDisplayName = if ($policy.displayName) { $policy.displayName } elseif ($policy.name) { $policy.name } else { $null }
                        if ($policyDisplayName -and -not $existingPolicies.ContainsKey($policyDisplayName)) {
                            $existingPolicies[$policyDisplayName] = $policy.id
                        }
                    }
                    $listUri = $existingResponse.'@odata.nextLink'
                } while ($listUri)
            }
            catch {
                # Endpoint might not support listing, continue without cache
                Write-Verbose "Could not cache policies from $endpoint - will check individually"
            }

            foreach ($jsonFile in $jsonFiles) {
                $folderCurrent++
                Write-Progress -Activity "Importing $osName/$folderName" -Status "$folderCurrent of $folderTotal" -PercentComplete (($folderCurrent / $folderTotal) * 100)

                $policyName = [System.IO.Path]::GetFileNameWithoutExtension($jsonFile.Name)

                try {
                    # Read JSON content and replace %OrganizationId% placeholder with actual tenant ID
                    $jsonContent = Get-Content -Path $jsonFile.FullName -Raw
                    if ($jsonContent -match '%OrganizationId%') {
                        Write-Verbose "Replacing %OrganizationId% with tenant ID in $policyName"
                        $jsonContent = $jsonContent -replace '%OrganizationId%', $TenantId
                    }
                    $policyContent = $jsonContent | ConvertFrom-Json

                    # Get display name from policy
                    $displayName = $policyContent.displayName
                    if (-not $displayName) {
                        $displayName = $policyContent.name
                    }
                    if (-not $displayName) {
                        $displayName = $policyName
                    }

                    # Check if policy exists using cached list
                    $existingPolicy = $existingPolicies.ContainsKey($displayName)

                    if ($existingPolicy -and $ImportMode -eq 'SkipIfExists') {
                        Write-HydrationLog -Message "  Skipped: $displayName" -Level Info
                        $results += New-HydrationResult -Name $displayName -Path $jsonFile.FullName -Type "$osName/$folderName" -Action 'Skipped' -Status 'Already exists'
                        continue
                    }

                    # Clean up import properties that shouldn't be sent
                    $importBody = Copy-DeepObject -InputObject $policyContent

                    # Remove read-only and system properties
                    Remove-ReadOnlyGraphProperties -InputObject $importBody -AdditionalProperties @(
                        'supportsScopeTags', 'deviceManagementApplicabilityRuleOsEdition',
                        'deviceManagementApplicabilityRuleOsVersion',
                        'deviceManagementApplicabilityRuleDeviceMode',
                        'creationSource', 'settingCount', 'priorityMetaData'
                    )

                    # Add hydration kit tag to description
                    $existingDesc = if ($importBody.description) { $importBody.description } else { "" }
                    $importBody.description = if ($existingDesc) { "$existingDesc - Imported by Intune-Hydration-Kit" } else { "Imported by Intune-Hydration-Kit" }

                    # Create the policy
                    $null = Invoke-MgGraphRequest -Method POST -Uri "beta/$endpoint" -Body ($importBody | ConvertTo-Json -Depth 100) -ContentType 'application/json' -ErrorAction Stop

                    Write-HydrationLog -Message "  Created: $displayName" -Level Info

                    $results += New-HydrationResult -Name $displayName -Path $jsonFile.FullName -Type "$osName/$folderName" -Action 'Created' -Status 'Success'
                }
                catch {
                    $errorMsg = Get-GraphErrorMessage -ErrorRecord $_
                    Write-HydrationLog -Message "  Failed: $policyName - $errorMsg" -Level Warning

                    $results += New-HydrationResult -Name $policyName -Path $jsonFile.FullName -Type "$osName/$folderName" -Action 'Failed' -Status $errorMsg
                }

                # Small delay to avoid rate limiting
                Start-Sleep -Milliseconds 100
            }
            Write-Progress -Activity "Importing $osName/$folderName" -Completed
        }

    }
    else {
        # WhatIf mode - just report what would be imported
        foreach ($policyFolder in $policyTypefolders) {
            $folder = $policyFolder.Folder
            $osName = $policyFolder.OsFolder
            $folderName = $policyFolder.PolicyType
            $jsonFiles = Get-ChildItem -Path $folder.FullName -Filter "*.json" -File -Recurse

            foreach ($jsonFile in $jsonFiles) {
                $policyName = [System.IO.Path]::GetFileNameWithoutExtension($jsonFile.Name)

                $results += New-HydrationResult -Name $policyName -Path $jsonFile.FullName -Type "$osName/$folderName" -Action 'WouldCreate' -Status 'DryRun'
            }
        }
    }

    return $results
}