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
        Import mode: AlwaysImport, SkipIfExists, Replace, Update
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
        [ValidateSet('SkipIfExists', 'Replace')]
        [string]$ImportMode = 'SkipIfExists',

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$RemoveExisting,

        [Parameter()]
        [switch]$TestMode
    )

    # Force switch sets ImportMode to Replace
    if ($Force) {
        $ImportMode = 'Replace'
    }

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

    # Remove existing baseline policies if requested - ONLY OIB policies (matching naming convention)
    if ($RemoveExisting) {
        Write-Host "Removing OpenIntuneBaseline policies..." -InformationAction Continue

        # OIB policies follow naming convention: "OS - OIB - Category - Type - Name - Version"
        # Examples: "MacOS - OIB - Compliance - U - Device Health - v1.0"
        #           "Windows - OIB - Defender - D - Attack Surface Reduction - v1.0"
        $oibPatterns = @(
            '- OIB -',
            'Android - Baseline -',
            'iOS - Baseline -'
        )

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

                        # Only delete if it matches OIB naming patterns
                        $isOibPolicy = $false
                        foreach ($pattern in $oibPatterns) {
                            if ($policyName -like "*$pattern*") {
                                $isOibPolicy = $true
                                break
                            }
                        }

                        if (-not $isOibPolicy) {
                            continue
                        }

                        if ($PSCmdlet.ShouldProcess($policyName, "Delete baseline policy")) {
                            try {
                                Invoke-MgGraphRequest -Method DELETE -Uri "$endpoint/$policyId" -ErrorAction Stop
                                Write-Host "Deleted: $policyName" -InformationAction Continue
                                $results += New-HydrationResult -Name $policyName -Type 'BaselinePolicy' -Action 'Deleted' -Status 'Success'
                            }
                            catch {
                                $errMessage = Get-GraphErrorMessage -ErrorRecord $_
                                Write-Warning "Failed to delete '$policyName': $errMessage"
                                $results += New-HydrationResult -Name $policyName -Type 'BaselinePolicy' -Action 'Failed' -Status "Delete failed: $errMessage"
                            }
                        }
                        else {
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

        # RemoveExisting mode - only delete, don't create
        $summary = Get-ResultSummary -Results $results
        Write-Host "Baseline removal complete: $($summary.Deleted) deleted, $($summary.Failed) failed" -InformationAction Continue
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
            Write-Host "Found $($jsonFiles.Count) policies in $($osFolder.Name)/$($subFolder.Name)" -InformationAction Continue
        }
    }

    Write-Host "Total policies to import: $totalPolicies" -InformationAction Continue

    # Test mode - only process first policy folder
    if ($TestMode -and $policyTypefolders.Count -gt 0) {
        $policyTypefolders = @($policyTypefolders[0])
        Write-Host "Test mode: Processing only first policy folder: $($policyTypefolders[0].OsFolder)/$($policyTypefolders[0].PolicyType)" -InformationAction Continue
    }

    if ($PSCmdlet.ShouldProcess("$totalPolicies policies from OpenIntuneBaseline", "Import to Intune")) {
        Write-Host "Starting direct Graph API import..." -InformationAction Continue

        foreach ($policyFolder in $policyTypefolders) {
            $folder = $policyFolder.Folder
            $folderName = $policyFolder.PolicyType
            $osName = $policyFolder.OsFolder
            $jsonFiles = Get-ChildItem -Path $folder.FullName -Filter "*.json" -File -Recurse

            # For IntuneManagement folders, try to import using @odata.type routing
            if ($folderName -in $intuneManagementFolders) {
                Write-Host "Processing $osName/$folderName - attempting Graph API import..." -InformationAction Continue

                foreach ($jsonFile in $jsonFiles) {
                    $policyName = [System.IO.Path]::GetFileNameWithoutExtension($jsonFile.Name)

                    try {
                        $policyContent = Get-Content -Path $jsonFile.FullName -Raw | ConvertFrom-Json
                        $odataType = $policyContent.'@odata.type'

                        # Determine endpoint from @odata.type
                        $typeEndpoint = $odataTypeToEndpoint[$odataType]
                        if (-not $typeEndpoint) {
                            Write-Warning "  Skipping $policyName - unsupported @odata.type: $odataType"
                            $results += New-HydrationResult -Name $policyName -Path $jsonFile.FullName -Type "$osName/$folderName" -Action 'Skipped' -Status "Unsupported @odata.type: $odataType"
                            continue
                        }

                        # Get display name
                        $displayName = $policyContent.displayName
                        if (-not $displayName) {
                            $displayName = $policyName
                        }

                        # Check if policy exists - use 'name' for configurationPolicies, 'displayName' for others
                        $existingPolicy = $null

                        # For Settings Catalog, check by 'name' property
                        if ($typeEndpoint -eq 'deviceManagement/configurationPolicies') {
                            try {
                                $checkUri = "beta/$typeEndpoint"
                                $listUri = $checkUri
                                do {
                                    $checkResponse = Invoke-MgGraphRequest -Method GET -Uri $listUri -ErrorAction Stop
                                    $existingPolicy = $checkResponse.value | Where-Object { $_.name -eq $displayName }
                                    if ($existingPolicy) { break }
                                    $listUri = $checkResponse.'@odata.nextLink'
                                } while ($listUri)
                            }
                            catch {
                                $existingPolicy = $null
                            }
                        }
                        else {
                            # For other types, fetch from this specific endpoint with pagination
                            try {
                                $listUri = "beta/$typeEndpoint"
                                do {
                                    $checkResponse = Invoke-MgGraphRequest -Method GET -Uri $listUri -ErrorAction Stop
                                    $existingPolicy = $checkResponse.value | Where-Object { $_.displayName -eq $displayName }
                                    if ($existingPolicy) { break }
                                    $listUri = $checkResponse.'@odata.nextLink'
                                } while ($listUri)
                            }
                            catch {
                                $existingPolicy = $null
                            }
                        }

                        if ($existingPolicy -and $ImportMode -eq 'SkipIfExists') {
                            Write-Host "  Skipping existing: $displayName" -InformationAction Continue
                            $results += New-HydrationResult -Name $displayName -Path $jsonFile.FullName -Type "$osName/$folderName" -Action 'Skipped' -Status 'Already exists'
                            continue
                        }

                        # Prepare import body - remove read-only and assignment properties
                        $importBody = [Management.Automation.PSSerializer]::Deserialize(
                            [Management.Automation.PSSerializer]::Serialize($policyContent)
                        )

                        $propsToRemove = @('id', 'createdDateTime', 'lastModifiedDateTime', 'version',
                                           'supportsScopeTags', 'deviceManagementApplicabilityRuleOsEdition',
                                           'deviceManagementApplicabilityRuleOsVersion',
                                           'deviceManagementApplicabilityRuleDeviceMode',
                                           '@odata.context', '@odata.id', '@odata.editLink',
                                           'creationSource', 'settingCount', 'priorityMetaData',
                                           'assignments', 'settingDefinitions', 'isAssigned')

                        foreach ($prop in $propsToRemove) {
                            if ($importBody.PSObject.Properties[$prop]) {
                                $importBody.PSObject.Properties.Remove($prop)
                            }
                        }

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
                        $response = Invoke-MgGraphRequest -Method POST -Uri "beta/$typeEndpoint" -Body ($importBody | ConvertTo-Json -Depth 100) -ContentType 'application/json' -ErrorAction Stop

                        Write-Host "  Created: $displayName" -InformationAction Continue
                        $results += New-HydrationResult -Name $displayName -Path $jsonFile.FullName -Type "$osName/$folderName" -Action 'Created' -Status 'Success'
                    }
                    catch {
                        $errorMsg = Get-GraphErrorMessage -ErrorRecord $_
                        Write-Warning "  Failed: $policyName - $errorMsg"
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

            Write-Host "Importing $($jsonFiles.Count) items from $osName/$folderName..." -InformationAction Continue

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
            }

            foreach ($jsonFile in $jsonFiles) {
                $folderCurrent++
                Write-Progress -Activity "Importing $osName/$folderName" -Status "$folderCurrent of $folderTotal" -PercentComplete (($folderCurrent / $folderTotal) * 100)

                $policyName = [System.IO.Path]::GetFileNameWithoutExtension($jsonFile.Name)

                try {
                    # Read and parse JSON
                    $policyContent = Get-Content -Path $jsonFile.FullName -Raw | ConvertFrom-Json

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
                        Write-Host "  Skipping existing: $displayName" -InformationAction Continue
                        $results += New-HydrationResult -Name $displayName -Path $jsonFile.FullName -Type "$osName/$folderName" -Action 'Skipped' -Status 'Already exists'
                        continue
                    }

                    # Clean up import properties that shouldn't be sent
                    $importBody = [Management.Automation.PSSerializer]::Deserialize(
                        [Management.Automation.PSSerializer]::Serialize($policyContent)
                    )

                    # Remove read-only and system properties
                    $propsToRemove = @('id', 'createdDateTime', 'lastModifiedDateTime', 'version',
                                       'supportsScopeTags', 'deviceManagementApplicabilityRuleOsEdition',
                                       'deviceManagementApplicabilityRuleOsVersion',
                                       'deviceManagementApplicabilityRuleDeviceMode',
                                       '@odata.context', 'creationSource', 'settingCount', 'priorityMetaData')

                    foreach ($prop in $propsToRemove) {
                        if ($importBody.PSObject.Properties[$prop]) {
                            $importBody.PSObject.Properties.Remove($prop)
                        }
                    }

                    # Add hydration kit tag to description
                    $existingDesc = if ($importBody.description) { $importBody.description } else { "" }
                    $importBody.description = if ($existingDesc) { "$existingDesc - Imported by Intune-Hydration-Kit" } else { "Imported by Intune-Hydration-Kit" }

                    # Create or update the policy
                    if ($existingPolicy -and $ImportMode -eq 'Replace') {
                        # Delete and recreate
                        $existingId = $existingPolicies[$displayName]
                        Invoke-MgGraphRequest -Method DELETE -Uri "beta/$endpoint/$existingId" -ErrorAction Stop
                        $response = Invoke-MgGraphRequest -Method POST -Uri "beta/$endpoint" -Body ($importBody | ConvertTo-Json -Depth 100) -ContentType 'application/json' -ErrorAction Stop
                        $action = 'Updated'
                    }
                    else {
                        $response = Invoke-MgGraphRequest -Method POST -Uri "beta/$endpoint" -Body ($importBody | ConvertTo-Json -Depth 100) -ContentType 'application/json' -ErrorAction Stop
                        $action = 'Created'
                    }

                    Write-Host "  $action : $displayName" -InformationAction Continue

                    $results += New-HydrationResult -Name $displayName -Path $jsonFile.FullName -Type "$osName/$folderName" -Action $action -Status 'Success'
                }
                catch {
                    $errorMsg = $_.Exception.Message
                    Write-Warning "  Failed: $policyName - $errorMsg"

                    $results += New-HydrationResult -Name $policyName -Path $jsonFile.FullName -Type "$osName/$folderName" -Action 'Failed' -Status $errorMsg
                }

                # Small delay to avoid rate limiting
                Start-Sleep -Milliseconds 100
            }
            Write-Progress -Activity "Importing $osName/$folderName" -Completed
        }

        $summary = Get-ResultSummary -Results $results

        Write-Host "Import completed. Created: $($summary.Created), Updated: $($summary.Updated), Skipped: $($summary.Skipped), Failed: $($summary.Failed)" -InformationAction Continue
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