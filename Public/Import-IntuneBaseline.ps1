function Import-IntuneBaseline {
    <#
    .SYNOPSIS
        Imports OpenIntuneBaseline policies from bundled templates
    .DESCRIPTION
        Imports OpenIntuneBaseline policies from the Templates/OpenIntuneBaseline directory.
        Supports Settings Catalog, Device Configuration, Compliance, and Update policies.
    .PARAMETER BaselinePath
        Path to the OpenIntuneBaseline directory (defaults to Templates/OpenIntuneBaseline)
    .PARAMETER IntuneManagementPath
        Path to IntuneManagement module (will download if not specified)
    .PARAMETER TenantId
        Target tenant ID (uses connected tenant if not specified)
    .PARAMETER ImportMode
        Import mode: SkipIfExists (default - skip policies that already exist)
    .PARAMETER IncludeAssignments
        Include policy assignments during import
    .PARAMETER Platform
        Filter baseline imports by platform. Valid values: Windows, macOS, iOS, Android, All.
        Defaults to 'All' which imports all baseline policies regardless of platform.
        - Windows: Imports from WINDOWS/ and WINDOWS365/ folders
        - macOS: Imports from MACOS/ folder
        - iOS/Android: Imports from BYOD/ folder (app protection policies)
    .EXAMPLE
        Import-IntuneBaseline
    .EXAMPLE
        Import-IntuneBaseline -BaselinePath ./OpenIntuneBaseline -ImportMode SkipIfExists
    .EXAMPLE
        Import-IntuneBaseline -Platform Windows,macOS
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [string]$BaselinePath,

        [Parameter()]
        [string]$TenantId,

        [Parameter()]
        [ValidateSet('Windows', 'macOS', 'iOS', 'Android', 'All')]
        [string[]]$Platform = @('All'),

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

    # Use bundled OpenIntuneBaseline templates if not provided (only needed for import, not delete)
    if (-not $RemoveExisting) {
        # If BaselinePath was provided but doesn't exist, fall back to bundled templates
        if ($BaselinePath -and -not (Test-Path -Path $BaselinePath)) {
            Write-Verbose "Specified BaselinePath '$BaselinePath' not found, using bundled templates"
            $BaselinePath = $null
        }

        if (-not $BaselinePath) {
            if ($script:TemplatesPath -and (Test-Path -Path $script:TemplatesPath)) {
                $BaselinePath = Join-Path -Path $script:TemplatesPath -ChildPath 'OpenIntuneBaseline'
            } elseif ($script:ModuleRoot -and (Test-Path -Path $script:ModuleRoot)) {
                $BaselinePath = Join-Path -Path $script:ModuleRoot -ChildPath 'Templates\OpenIntuneBaseline'
            } else {
                # Fallback: Calculate from this function's script file location
                $scriptPath = $MyInvocation.MyCommand.ScriptBlock.File
                if ($scriptPath) {
                    $moduleRoot = Split-Path -Parent (Split-Path -Parent $scriptPath)
                    $BaselinePath = Join-Path -Path $moduleRoot -ChildPath 'Templates\OpenIntuneBaseline'
                } else {
                    throw "Cannot determine OpenIntuneBaseline path. Please specify -BaselinePath parameter."
                }
            }
        }

        if (-not (Test-Path -Path $BaselinePath)) {
            throw "OpenIntuneBaseline templates not found at: $BaselinePath"
        }
    }

    # OpenIntuneBaseline uses OS-based folder structure:
    # - OS/IntuneManagement/ - Exported by IntuneManagement tool (requires Windows GUI to import)
    # - OS/NativeImport/ - Settings Catalog policies that can be imported via Graph API
    # - BYOD/AppProtection/ - App protection policies

    # Map folder names to Graph API endpoints (normalized names only, no duplicates)
    $endpointMap = @{
        'NativeImport'                     = 'deviceManagement/configurationPolicies'
        'AppProtection'                    = 'deviceAppManagement/managedAppPolicies'
        'Administrative Templates'         = 'deviceManagement/groupPolicyConfigurations'
        'Compliance'                       = 'deviceManagement/deviceCompliancePolicies'
        'Compliance Policies'              = 'deviceManagement/deviceCompliancePolicies'
        'Configuration Profiles'           = 'deviceManagement/deviceConfigurations'
        'Device Configuration'             = 'deviceManagement/deviceConfigurations'
        'Device Enrollment Configurations' = 'deviceManagement/deviceEnrollmentConfigurations'
        'Endpoint Security'                = 'deviceManagement/intents'
        'Settings Catalog'                 = 'deviceManagement/configurationPolicies'
        'Scripts'                          = 'deviceManagement/deviceManagementScripts'
        'Proactive Remediations'           = 'deviceManagement/deviceHealthScripts'
        'Windows Autopilot'                = 'deviceManagement/windowsAutopilotDeploymentProfiles'
        'App Configuration'                = 'deviceAppManagement/mobileAppConfigurations'
        'App Protection Policies'          = 'deviceAppManagement/managedAppPolicies'
    }

    # Map @odata.type to Graph API endpoints for IntuneManagement exports
    $odataTypeToEndpoint = @{
        # Device Configurations
        '#microsoft.graph.windowsHealthMonitoringConfiguration'         = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.windows10GeneralConfiguration'                = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.windows10EndpointProtectionConfiguration'     = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.windows10CustomConfiguration'                 = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.windowsDeliveryOptimizationConfiguration'     = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.windowsUpdateForBusinessConfiguration'        = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.windowsIdentityProtectionConfiguration'       = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.windowsKioskConfiguration'                    = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.editionUpgradeConfiguration'                  = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.sharedPCConfiguration'                        = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.windowsWifiConfiguration'                     = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.windowsWiredNetworkConfiguration'             = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.macOSGeneralDeviceConfiguration'              = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.macOSCustomConfiguration'                     = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.macOSEndpointProtectionConfiguration'         = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.iosGeneralDeviceConfiguration'                = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.iosCustomConfiguration'                       = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.androidGeneralDeviceConfiguration'            = 'deviceManagement/deviceConfigurations'
        '#microsoft.graph.androidWorkProfileGeneralDeviceConfiguration' = 'deviceManagement/deviceConfigurations'
        # Compliance Policies
        '#microsoft.graph.windows10CompliancePolicy'                    = 'deviceManagement/deviceCompliancePolicies'
        '#microsoft.graph.windows81CompliancePolicy'                    = 'deviceManagement/deviceCompliancePolicies'
        '#microsoft.graph.macOSCompliancePolicy'                        = 'deviceManagement/deviceCompliancePolicies'
        '#microsoft.graph.iosCompliancePolicy'                          = 'deviceManagement/deviceCompliancePolicies'
        '#microsoft.graph.androidCompliancePolicy'                      = 'deviceManagement/deviceCompliancePolicies'
        '#microsoft.graph.androidWorkProfileCompliancePolicy'           = 'deviceManagement/deviceCompliancePolicies'
        '#microsoft.graph.androidDeviceOwnerCompliancePolicy'           = 'deviceManagement/deviceCompliancePolicies'
        # Settings Catalog / Configuration Policies
        '#microsoft.graph.deviceManagementConfigurationPolicy'          = 'deviceManagement/configurationPolicies'
        # Windows Update for Business - Driver Updates
        '#microsoft.graph.windowsDriverUpdateProfile'                   = 'deviceManagement/windowsDriverUpdateProfiles'
    }

    # Folders that previously required IntuneManagement tool - now we try to import via Graph API
    $intuneManagementFolders = @('IntuneManagement')

    # Folders to skip - NativeImport duplicates policies from IntuneManagement with fewer options
    $skipFolders = @('NativeImport')

    $results = @()

    # Check Windows Driver Update license upfront (cached for all driver update profiles)
    $hasDriverUpdateLicense = $null  # Lazy-loaded when needed

    # Remove existing baseline policies if requested
    # SAFETY: Only delete policies that have "Imported by Intune Hydration Kit" in description
    if ($RemoveExisting) {
        $maxBatchSize = if ($script:MaxBatchSize) { $script:MaxBatchSize } else { 10 }
        $maxRetries = 3
        $retryDelaySeconds = 2

        # Delete from main endpoints used by baselines
        # Note: App protection policies are handled separately by Import-IntuneAppProtectionPolicy
        $deleteEndpoints = @(
            'beta/deviceManagement/configurationPolicies',
            'beta/deviceManagement/deviceConfigurations',
            'beta/deviceManagement/deviceCompliancePolicies'
        )

        # Collect all policies to delete across all endpoints
        $policiesToDelete = @()
        foreach ($endpoint in $deleteEndpoints) {
            try {
                $listUri = $endpoint
                do {
                    $existing = Invoke-MgGraphRequest -Method GET -Uri $listUri -ErrorAction Stop
                    foreach ($policy in $existing.value) {
                        $policyName = if ($policy.displayName) { $policy.displayName } elseif ($policy.name) { $policy.name } else { "Unknown" }

                        # Safety check: Only delete if created by this kit (has hydration marker in description)
                        if (-not (Test-HydrationKitObject -Description $policy.description -ObjectName $policyName)) {
                            Write-Verbose "Skipping '$policyName' - not created by Intune Hydration Kit"
                            continue
                        }

                        $policiesToDelete += @{
                            Name     = $policyName
                            Id       = $policy.id
                            Endpoint = $endpoint
                        }
                    }
                    $listUri = $existing.'@odata.nextLink'
                } while ($listUri)
            } catch {
                Write-Warning "Failed to list policies from $endpoint : $_"
            }
        }

        if ($policiesToDelete.Count -eq 0) {
            Write-Verbose "No baseline policies found to delete"
            return $results
        }

        # Handle WhatIf mode
        if (-not $PSCmdlet.ShouldProcess("$($policiesToDelete.Count) baseline policies", "Delete")) {
            foreach ($policy in $policiesToDelete) {
                Write-HydrationLog -Message "  WouldDelete: $($policy.Name)" -Level Info
                $results += New-HydrationResult -Name $policy.Name -Type 'BaselinePolicy' -Action 'WouldDelete' -Status 'DryRun'
            }
            return $results
        }

        # Batch delete policies with retry logic
        Write-Verbose "Deleting $($policiesToDelete.Count) baseline policies in batches..."
        for ($batchStart = 0; $batchStart -lt $policiesToDelete.Count; $batchStart += $maxBatchSize) {
            $batchEnd = [Math]::Min($batchStart + $maxBatchSize, $policiesToDelete.Count) - 1
            $currentBatch = $policiesToDelete[$batchStart..$batchEnd]

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
                    $policy = $pendingItems[$i]
                    # Strip 'beta/' prefix from endpoint for batch URL
                    $batchUrl = "/$($policy.Endpoint -replace '^beta/', '')/$($policy.Id)"
                    $batchRequests += @{
                        id     = ($i + 1).ToString()
                        method = "DELETE"
                        url    = $batchUrl
                    }
                }

                $batchBody = @{ requests = $batchRequests }
                $itemsToRetry = @()

                try {
                    $batchResponse = Invoke-MgGraphRequest -Method POST -Uri "beta/`$batch" -Body $batchBody -ErrorAction Stop

                    foreach ($resp in $batchResponse.responses) {
                        $requestIndex = [int]$resp.id - 1
                        $policy = $pendingItems[$requestIndex]

                        if ($resp.status -eq 204 -or $resp.status -eq 200) {
                            Write-HydrationLog -Message "  Deleted: $($policy.Name)" -Level Info
                            $results += New-HydrationResult -Name $policy.Name -Type 'BaselinePolicy' -Action 'Deleted' -Status 'Success'
                        } elseif ($resp.status -eq 404) {
                            Write-HydrationLog -Message "  Skipped: $($policy.Name) (already deleted)" -Level Info
                            $results += New-HydrationResult -Name $policy.Name -Type 'BaselinePolicy' -Action 'Skipped' -Status 'Already deleted'
                        } elseif ($resp.status -ge 500 -and $retryCount -lt $maxRetries) {
                            Write-Verbose "Server error ($($resp.status)) for '$($policy.Name)' - will retry"
                            $itemsToRetry += $policy
                        } else {
                            $errorMessage = if ($resp.body.error.message) { $resp.body.error.message } else { "HTTP $($resp.status)" }
                            Write-HydrationLog -Message "  [!] Failed: $($policy.Name) - $errorMessage" -Level Warning
                            $results += New-HydrationResult -Name $policy.Name -Type 'BaselinePolicy' -Action 'Failed' -Status "Delete failed: $errorMessage"
                        }
                    }
                } catch {
                    if ($retryCount -lt $maxRetries) {
                        Write-Verbose "Batch delete failed, will retry: $_"
                        $itemsToRetry = $pendingItems
                    } else {
                        Write-Warning "Batch delete failed: $_"
                        foreach ($policy in $pendingItems) {
                            $results += New-HydrationResult -Name $policy.Name -Type 'BaselinePolicy' -Action 'Failed' -Status "Batch delete failed: $_"
                        }
                    }
                }

                $pendingItems = $itemsToRetry
                $retryCount++
            }
        }

        return $results
    }

    # Find all policy type subfolders within OS folders (WINDOWS, MACOS, BYOD, WINDOWS365)
    # OpenIntuneBaseline structure: OS/PolicyType/policy.json

    # Platform to folder mapping for filtering
    $platformFolderMapping = @{
        'Windows' = @('WINDOWS', 'WINDOWS365', 'Windows', 'Windows365')
        'macOS'   = @('MACOS', 'macOS', 'MacOS')
        'iOS'     = @('BYOD', 'byod')
        'Android' = @('BYOD', 'byod')
    }

    $osFolders = Get-ChildItem -Path $BaselinePath -Directory | Where-Object {
        $_.Name -notmatch '^\.'
    }

    # Filter OS folders by platform if specified
    if ($Platform -and $Platform -notcontains 'All') {
        $allowedFolders = @()
        foreach ($plat in $Platform) {
            if ($platformFolderMapping.ContainsKey($plat)) {
                $allowedFolders += $platformFolderMapping[$plat]
            }
        }
        $allowedFolders = $allowedFolders | Select-Object -Unique

        $osFolders = $osFolders | Where-Object {
            $folderName = $_.Name
            $allowedFolders -contains $folderName
        }

        Write-Verbose "Platform filter active: Processing folders: $($osFolders.Name -join ', ')"
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
                Folder     = $subFolder
                OsFolder   = $osFolder.Name
                PolicyType = $subFolder.Name
            }
        }
    }

    if ($PSCmdlet.ShouldProcess("$totalPolicies policies from OpenIntuneBaseline", "Import to Intune")) {
        $maxBatchSize = if ($script:MaxBatchSize) { $script:MaxBatchSize } else { 10 }
        $maxRetries = 3
        $retryDelaySeconds = 2

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
            } catch {
                # Endpoint might not support listing, continue without cache for this endpoint
                Write-Verbose "Could not cache policies from $cacheEndpoint - will check individually"
            }
        }

        # Collect all policies to create with their prepared bodies
        $policiesToCreate = @()

        foreach ($policyFolder in $policyTypefolders) {
            $folder = $policyFolder.Folder
            $folderName = $policyFolder.PolicyType
            $osName = $policyFolder.OsFolder

            # Skip folders that duplicate content from other folders (e.g., NativeImport duplicates IntuneManagement)
            if ($folderName -in $skipFolders) {
                Write-Verbose "Skipping $osName/$folderName - duplicates content from IntuneManagement folder"
                continue
            }

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
                        $importBody.description = if ($existingDesc) { "$existingDesc - Imported by Intune Hydration Kit" } else { "Imported by Intune Hydration Kit" }

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

                            # Build a clean body with only the required properties
                            $cleanBody = @{
                                name         = $importBody.name
                                description  = $importBody.description
                                platforms    = $importBody.platforms
                                technologies = $importBody.technologies
                                settings     = @()
                            }

                            # Add optional properties if present
                            if ($importBody.roleScopeTagIds) {
                                $cleanBody.roleScopeTagIds = $importBody.roleScopeTagIds
                            }
                            if ($importBody.templateReference -and $importBody.templateReference.templateId) {
                                $cleanBody.templateReference = @{
                                    templateId = $importBody.templateReference.templateId
                                }
                            }

                            # Clean settings - remove id and odata navigation properties from each setting
                            if ($importBody.settings) {
                                foreach ($setting in $importBody.settings) {
                                    $cleanSetting = $setting | ConvertTo-Json -Depth 100 -Compress | ConvertFrom-Json

                                    # Remove read-only properties from the setting
                                    $propsToRemove = @($cleanSetting.PSObject.Properties | Where-Object {
                                            $_.Name -eq 'id' -or $_.Name -match '@odata\.' -or $_.Name -eq 'settingDefinitions'
                                        })
                                    foreach ($prop in $propsToRemove) {
                                        $cleanSetting.PSObject.Properties.Remove($prop.Name)
                                    }

                                    $cleanBody.settings += $cleanSetting
                                }
                            }

                            $importBody = [PSCustomObject]$cleanBody
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
                                            actionType                = $config.actionType
                                            gracePeriodHours          = [int]$config.gracePeriodHours
                                            notificationTemplateId    = if ($config.notificationTemplateId) { $config.notificationTemplateId } else { "" }
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

                        # Add to collection for batch creation
                        # Store body as JSON string to avoid PowerShell serialization issues with circular references
                        $policiesToCreate += @{
                            Name     = $displayName
                            Path     = $jsonFile.FullName
                            Type     = "$osName/$folderName"
                            Endpoint = $typeEndpoint
                            BodyJson = ($importBody | ConvertTo-Json -Depth 100 -Compress)
                        }
                    } catch {
                        $errorMsg = Get-GraphErrorMessage -ErrorRecord $_
                        Write-HydrationLog -Message "  Failed to prepare: $policyName - $errorMsg" -Level Warning
                        $results += New-HydrationResult -Name $policyName -Path $jsonFile.FullName -Type "$osName/$folderName" -Action 'Failed' -Status "Prepare error: $errorMsg"
                    }
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
            } catch {
                # Endpoint might not support listing, continue without cache
                Write-Verbose "Could not cache policies from $endpoint - will check individually"
            }

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
                    $importBody.description = if ($existingDesc) { "$existingDesc - Imported by Intune Hydration Kit" } else { "Imported by Intune Hydration Kit" }

                    # Add to collection for batch creation
                    # Store body as JSON string to avoid PowerShell serialization issues with circular references
                    $policiesToCreate += @{
                        Name     = $displayName
                        Path     = $jsonFile.FullName
                        Type     = "$osName/$folderName"
                        Endpoint = $endpoint
                        BodyJson = ($importBody | ConvertTo-Json -Depth 100 -Compress)
                    }
                } catch {
                    $errorMsg = Get-GraphErrorMessage -ErrorRecord $_
                    Write-HydrationLog -Message "  Failed to prepare: $policyName - $errorMsg" -Level Warning
                    $results += New-HydrationResult -Name $policyName -Path $jsonFile.FullName -Type "$osName/$folderName" -Action 'Failed' -Status "Prepare error: $errorMsg"
                }
            }
        }

        # Batch create all collected policies with retry logic
        if ($policiesToCreate.Count -gt 0) {
            Write-Verbose "Creating $($policiesToCreate.Count) baseline policies in batches..."

            for ($batchStart = 0; $batchStart -lt $policiesToCreate.Count; $batchStart += $maxBatchSize) {
                $batchEnd = [Math]::Min($batchStart + $maxBatchSize, $policiesToCreate.Count) - 1
                $currentBatch = $policiesToCreate[$batchStart..$batchEnd]

                # Track which items need retry
                $pendingItems = @($currentBatch)
                $retryCount = 0

                while ($pendingItems.Count -gt 0 -and $retryCount -le $maxRetries) {
                    if ($retryCount -gt 0) {
                        $delay = $retryDelaySeconds * [Math]::Pow(2, $retryCount - 1)
                        Write-Verbose "Retrying $($pendingItems.Count) failed create(s) after ${delay}s delay (attempt $retryCount of $maxRetries)..."
                        Start-Sleep -Seconds $delay
                    }

                    # Build batch request as JSON string to avoid PowerShell serialization issues
                    $batchRequestsJson = @()
                    for ($i = 0; $i -lt $pendingItems.Count; $i++) {
                        $policy = $pendingItems[$i]
                        # Build each request as a JSON string fragment
                        $requestJson = "{`"id`":`"$(($i + 1).ToString())`",`"method`":`"POST`",`"url`":`"/$($policy.Endpoint)`",`"headers`":{`"Content-Type`":`"application/json`"},`"body`":$($policy.BodyJson)}"
                        $batchRequestsJson += $requestJson
                    }

                    $batchBodyJson = "{`"requests`":[" + ($batchRequestsJson -join ",") + "]}"
                    $itemsToRetry = @()

                    try {
                        $batchResponse = Invoke-MgGraphRequest -Method POST -Uri "beta/`$batch" -Body $batchBodyJson -ContentType 'application/json' -ErrorAction Stop

                        foreach ($resp in $batchResponse.responses) {
                            $requestIndex = [int]$resp.id - 1
                            $policy = $pendingItems[$requestIndex]

                            if ($resp.status -eq 201 -or $resp.status -eq 200) {
                                Write-HydrationLog -Message "  Created: $($policy.Name)" -Level Info
                                $results += New-HydrationResult -Name $policy.Name -Path $policy.Path -Type $policy.Type -Action 'Created' -Status 'Success'
                            } elseif ($resp.status -eq 409) {
                                # Conflict - policy was created between check and creation (race condition)
                                Write-HydrationLog -Message "  Skipped: $($policy.Name) (race condition)" -Level Info
                                $results += New-HydrationResult -Name $policy.Name -Path $policy.Path -Type $policy.Type -Action 'Skipped' -Status 'Already exists (race condition)'
                            } elseif ($resp.status -ge 500 -and $retryCount -lt $maxRetries) {
                                Write-Verbose "Server error ($($resp.status)) for '$($policy.Name)' - will retry"
                                $itemsToRetry += $policy
                            } else {
                                $errorMessage = if ($resp.body.error.message) { $resp.body.error.message } else { "HTTP $($resp.status)" }
                                Write-HydrationLog -Message "  [!] Failed: $($policy.Name) - $errorMessage" -Level Warning
                                $results += New-HydrationResult -Name $policy.Name -Path $policy.Path -Type $policy.Type -Action 'Failed' -Status $errorMessage
                            }
                        }
                    } catch {
                        if ($retryCount -lt $maxRetries) {
                            Write-Verbose "Batch create failed, will retry: $_"
                            $itemsToRetry = $pendingItems
                        } else {
                            Write-Warning "Batch create failed: $_"
                            foreach ($policy in $pendingItems) {
                                $results += New-HydrationResult -Name $policy.Name -Path $policy.Path -Type $policy.Type -Action 'Failed' -Status "Batch create failed: $_"
                            }
                        }
                    }

                    $pendingItems = $itemsToRetry
                    $retryCount++
                }
            }
        }

    } else {
        # WhatIf mode - just report what would be imported
        foreach ($policyFolder in $policyTypefolders) {
            $folder = $policyFolder.Folder
            $osName = $policyFolder.OsFolder
            $folderName = $policyFolder.PolicyType

            # Skip folders that duplicate content from other folders
            if ($folderName -in $skipFolders) {
                continue
            }

            $jsonFiles = Get-ChildItem -Path $folder.FullName -Filter "*.json" -File -Recurse

            foreach ($jsonFile in $jsonFiles) {
                $policyName = [System.IO.Path]::GetFileNameWithoutExtension($jsonFile.Name)

                $results += New-HydrationResult -Name $policyName -Path $jsonFile.FullName -Type "$osName/$folderName" -Action 'WouldCreate' -Status 'DryRun'
            }
        }
    }

    return $results
}