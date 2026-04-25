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

    if (-not $TenantId) {
        $TenantId = $script:HydrationState.TenantId
    }

    if (-not $TenantId) {
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("TenantId is required. Either connect using Connect-IntuneHydration or specify -TenantId parameter."),
            'MissingTenantId',
            [System.Management.Automation.ErrorCategory]::InvalidArgument,
            $null
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    # Resolve BaselinePath to bundled templates if not provided
    if ($BaselinePath -and -not (Test-Path -Path $BaselinePath)) {
        Write-Verbose "Specified BaselinePath '$BaselinePath' not found, using bundled templates"
        $BaselinePath = $null
    }

    if (-not $BaselinePath) {
        if ($script:TemplatesPath -and (Test-Path -Path $script:TemplatesPath)) {
            $BaselinePath = Join-Path -Path $script:TemplatesPath -ChildPath 'OpenIntuneBaseline'
        } elseif ($script:ModuleRoot -and (Test-Path -Path $script:ModuleRoot)) {
            $BaselinePath = Join-Path -Path (Join-Path -Path $script:ModuleRoot -ChildPath 'Templates') -ChildPath 'OpenIntuneBaseline'
        } else {
            # Fallback: Calculate from this function's script file location
            $scriptPath = $MyInvocation.MyCommand.ScriptBlock.File
            if ($scriptPath) {
                $moduleRoot = Split-Path -Parent (Split-Path -Parent $scriptPath)
                $BaselinePath = Join-Path -Path (Join-Path -Path $moduleRoot -ChildPath 'Templates') -ChildPath 'OpenIntuneBaseline'
            } elseif (-not $RemoveExisting) {
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("Cannot determine OpenIntuneBaseline path. Please specify -BaselinePath parameter."),
                    'BaselinePathNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $null
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
        }
    }

    if (-not $RemoveExisting -and (-not $BaselinePath -or -not (Test-Path -Path $BaselinePath))) {
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("OpenIntuneBaseline templates not found at: $BaselinePath"),
            'BaselineTemplatesNotFound',
            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
            $BaselinePath
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    # OpenIntuneBaseline uses OS-based folder structure:
    # - OS/IntuneManagement/ - Exported by IntuneManagement tool (requires Windows GUI to import)
    # - OS/NativeImport/ - Settings Catalog policies that can be imported via Graph API
    # - BYOD/AppProtection/ - App protection policies

    $importMetadata = Get-BaselineImportMetadata -Kind 'OpenIntune'
    $endpointMap = $importMetadata.EndpointMap
    $odataTypeToEndpoint = $importMetadata.ODataTypeToEndpoint
    $intuneManagementFolders = $importMetadata.IntuneManagementFolders
    $skipFolders = $importMetadata.SkipFolders

    $results = @()

    # Check Windows Driver Update license upfront (cached for all driver update profiles)
    $hasDriverUpdateLicense = $null  # Lazy-loaded when needed

    # Remove existing baseline policies if requested
    # SAFETY: Only delete policies that have "Imported by Intune Hydration Kit" in description
    if ($RemoveExisting) {
        # Load template names to scope deletes to only policies this kit would create
        $knownTemplateNames = Get-TemplateDisplayNames -Path $BaselinePath -Recurse

        # Delete from all endpoints used by baselines
        # Shared endpoints always included; platform-specific endpoints scoped by -Platform
        $deleteEndpoints = @(
            'beta/deviceManagement/configurationPolicies',
            'beta/deviceManagement/deviceConfigurations',
            'beta/deviceManagement/deviceCompliancePolicies'
        )

        # Add platform-specific endpoints only when that platform is in scope
        if (-not $Platform -or $Platform -contains 'All' -or $Platform -contains 'Windows') {
            $deleteEndpoints += 'beta/deviceManagement/windowsDriverUpdateProfiles'
        }
        if (-not $Platform -or $Platform -contains 'All' -or $Platform -contains 'Android') {
            $deleteEndpoints += 'beta/deviceAppManagement/androidManagedAppProtections'
        }
        if (-not $Platform -or $Platform -contains 'All' -or $Platform -contains 'iOS') {
            $deleteEndpoints += 'beta/deviceAppManagement/iosManagedAppProtections'
        }

        $policiesToDelete = Get-HydrationDeleteCandidates -Endpoint $deleteEndpoints -KnownTemplateNames $knownTemplateNames

        if ($policiesToDelete.Count -eq 0) {
            Write-Verbose "No baseline policies found to delete"
            return $results
        }

        # Handle WhatIf mode
        if (-not $PSCmdlet.ShouldProcess("$($policiesToDelete.Count) baseline policies", "Delete")) {
            if ($WhatIfPreference) {
                foreach ($policy in $policiesToDelete) {
                    Write-HydrationLog -Message "  WouldDelete: $($policy.Name)" -Level Info
                    $results += New-HydrationResult -Name $policy.Name -Type 'BaselinePolicy' -Action 'WouldDelete' -Status 'DryRun'
                }
            }
            return $results
        }

        # Batch delete policies using centralized helper
        $results += Invoke-GraphBatchOperation -Items $policiesToDelete -Operation 'DELETE' -ResultType 'BaselinePolicy'

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

    $shouldImport = $PSCmdlet.ShouldProcess("$totalPolicies policies from OpenIntuneBaseline", "Import to Intune")
    if (-not $shouldImport -and -not $WhatIfPreference) {
        return $results
    }

    $logParams = @{
        Message = "Discovered $totalPolicies OpenIntuneBaseline templates across $($policyTypefolders.Count) folders"
        Level   = 'Info'
    }
    Write-HydrationLog @logParams

    # Pre-fetch existing policies from all unique endpoints to avoid repeated API calls
    $endpointPolicyCache = @{}
    $uniqueEndpoints = $odataTypeToEndpoint.Values | Sort-Object -Unique
    $cacheIndex = 0
    foreach ($cacheEndpoint in $uniqueEndpoints) {
        $cacheIndex++
        $logParams = @{
            Message = "Caching existing policies ($cacheIndex/$($uniqueEndpoints.Count)): $cacheEndpoint"
            Level   = 'Info'
        }
        Write-HydrationLog @logParams
        $endpointPolicyCache[$cacheEndpoint] = @{}
        try {
            Get-GraphPagedResults -Uri "beta/$cacheEndpoint" -ProcessItems {
                param($items)
                foreach ($policy in $items) {
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
            }
        } catch {
            # Endpoint might not support listing, continue without cache for this endpoint
            Write-Verbose "Could not cache policies from $cacheEndpoint - will check individually"
        }
    }

    $logParams = @{
        Message = 'Caching complete. Preparing OpenIntuneBaseline payloads...'
        Level   = 'Info'
    }
    Write-HydrationLog @logParams

    # Collect all policies to create with their prepared bodies
    $policiesToCreate = @()
    $activePolicyFolders = @($policyTypefolders | Where-Object { $_.PolicyType -notin $skipFolders })
    $folderIndex = 0

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
        $folderIndex++
        $logParams = @{
            Message = "Preparing OpenIntuneBaseline folder ($folderIndex/$($activePolicyFolders.Count)): $osName/$folderName ($($jsonFiles.Count) templates)"
            Level   = 'Info'
        }
        Write-HydrationLog @logParams

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

                    # Get display name with import prefix
                    $displayName = if ($policyContent.displayName) {
                        "$($script:ImportPrefix)$($policyContent.displayName)"
                    } else {
                        "$($script:ImportPrefix)$policyName"
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
                    $importBody.description = New-HydrationDescription -ExistingText $importBody.description

                    # Apply import prefix to body properties
                    if ($importBody.displayName) { $importBody.displayName = $displayName }
                    if ($importBody.name) { $importBody.name = $displayName }

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
                        Url      = "/$typeEndpoint"
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
            Get-GraphPagedResults -Uri "beta/$endpoint" -ProcessItems {
                param($items)
                foreach ($policy in $items) {
                    $policyDisplayName = if ($policy.displayName) { $policy.displayName } elseif ($policy.name) { $policy.name } else { $null }
                    if ($policyDisplayName -and -not $existingPolicies.ContainsKey($policyDisplayName)) {
                        $existingPolicies[$policyDisplayName] = $policy.id
                    }
                }
            }
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

                # Get display name from policy with import prefix
                $displayName = if ($policyContent.displayName) {
                    "$($script:ImportPrefix)$($policyContent.displayName)"
                } elseif ($policyContent.name) {
                    "$($script:ImportPrefix)$($policyContent.name)"
                } else {
                    "$($script:ImportPrefix)$policyName"
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
                $importBody.description = New-HydrationDescription -ExistingText $importBody.description

                # Apply import prefix to body properties
                if ($importBody.displayName) { $importBody.displayName = $displayName }
                if ($importBody.name) { $importBody.name = $displayName }

                # Add to collection for batch creation
                # Store body as JSON string to avoid PowerShell serialization issues with circular references
                $policiesToCreate += @{
                    Name     = $displayName
                    Path     = $jsonFile.FullName
                    Type     = "$osName/$folderName"
                    Url      = "/$endpoint"
                    BodyJson = ($importBody | ConvertTo-Json -Depth 100 -Compress)
                }
            } catch {
                $errorMsg = Get-GraphErrorMessage -ErrorRecord $_
                Write-HydrationLog -Message "  Failed to prepare: $policyName - $errorMsg" -Level Warning
                $results += New-HydrationResult -Name $policyName -Path $jsonFile.FullName -Type "$osName/$folderName" -Action 'Failed' -Status "Prepare error: $errorMsg"
            }
        }
    }

    # Batch create all collected policies using centralized helper
    if ($policiesToCreate.Count -gt 0) {
        if ($shouldImport) {
            $logParams = @{
                Message = "Prepared $($policiesToCreate.Count) OpenIntuneBaseline payloads. Starting batch import..."
                Level   = 'Info'
            }
            Write-HydrationLog @logParams
            $results += Invoke-GraphBatchOperation -Items $policiesToCreate -Operation 'POST' -ResultType 'BaselinePolicy'
        } else {
            $logParams = @{
                Message = "Prepared $($policiesToCreate.Count) OpenIntuneBaseline payloads. Reporting WhatIf results..."
                Level   = 'Info'
            }
            Write-HydrationLog @logParams

            foreach ($policyToCreate in $policiesToCreate) {
                $results += New-HydrationResult -Name $policyToCreate.Name -Path $policyToCreate.Path -Type $policyToCreate.Type -Action 'WouldCreate' -Status 'DryRun'
            }
        }
    }

    return $results
}
