function Import-CISBaseline {
    <#
    .SYNOPSIS
        Imports CIS Baseline policies from bundled templates
    .DESCRIPTION
        Imports CIS Benchmark and industry baseline policies from the Templates/CISBaselines directory.
        Supports Settings Catalog, Compliance, and Device Configuration policies.
        Routes each policy to the correct Graph API endpoint based on its @odata.type property.
    .PARAMETER BaselinePath
        Path to the CISBaselines directory (defaults to Templates/CISBaselines)
    .PARAMETER TenantId
        Target tenant ID (uses connected tenant if not specified)
    .PARAMETER Platform
        Filter imports by platform. Valid values: Windows, macOS, iOS, Android, Linux, All.
        Defaults to 'All'. Filters based on the 'platforms' property inside each JSON policy.
    .PARAMETER ImportMode
        Import mode: SkipIfExists (default - skip policies that already exist)
    .PARAMETER RemoveExisting
        Delete existing CIS baseline policies created by this kit instead of importing
    .EXAMPLE
        Import-CISBaseline
    .EXAMPLE
        Import-CISBaseline -Platform Windows
    .EXAMPLE
        Import-CISBaseline -RemoveExisting
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [string]$BaselinePath,

        [Parameter()]
        [string]$TenantId,

        [Parameter()]
        [ValidateSet('Windows', 'macOS', 'iOS', 'Android', 'Linux', 'All')]
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
            $BaselinePath = Join-Path -Path $script:TemplatesPath -ChildPath 'CISBaselines'
        } elseif ($script:ModuleRoot -and (Test-Path -Path $script:ModuleRoot)) {
            $BaselinePath = Join-Path -Path (Join-Path -Path $script:ModuleRoot -ChildPath 'Templates') -ChildPath 'CISBaselines'
        } else {
            $scriptPath = $MyInvocation.MyCommand.ScriptBlock.File
            if ($scriptPath) {
                $moduleRoot = Split-Path -Parent (Split-Path -Parent $scriptPath)
                $BaselinePath = Join-Path -Path (Join-Path -Path $moduleRoot -ChildPath 'Templates') -ChildPath 'CISBaselines'
            } elseif (-not $RemoveExisting) {
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("Cannot determine CIS Baselines path. Please specify -BaselinePath parameter."),
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
            [System.Exception]::new("CIS Baseline templates not found at: $BaselinePath"),
            'BaselineTemplatesNotFound',
            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
            $BaselinePath
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    $importMetadata = Get-BaselineImportMetadata -Kind 'CIS'
    $odataTypeToEndpoint = $importMetadata.ODataTypeToEndpoint
    $odataContextToEndpoint = $importMetadata.ODataContextToEndpoint
    $platformValueMapping = $importMetadata.PlatformValueMapping

    $results = @()

    # Remove existing CIS baseline policies if requested
    if ($RemoveExisting) {
        $knownTemplateNames = Get-TemplateDisplayNames -Path $BaselinePath -NameProperty 'name' -Recurse

        $deleteEndpoints = @(
            'beta/deviceManagement/configurationPolicies',
            'beta/deviceManagement/groupPolicyConfigurations',
            'beta/deviceManagement/intents',
            'beta/deviceManagement/compliancePolicies',
            'beta/deviceManagement/deviceCompliancePolicies',
            'beta/deviceManagement/deviceConfigurations'
        )

        $policiesToDelete = Get-HydrationDeleteCandidates -Endpoint $deleteEndpoints -KnownTemplateNames $knownTemplateNames -RequireTemplateMatch

        if ($policiesToDelete.Count -eq 0) {
            Write-Verbose "No CIS baseline policies found to delete"
            return $results
        }

        if (-not $PSCmdlet.ShouldProcess("$($policiesToDelete.Count) CIS baseline policies", "Delete")) {
            if ($WhatIfPreference) {
                foreach ($policy in $policiesToDelete) {
                    Write-HydrationLog -Message "  WouldDelete: $($policy.Name)" -Level Info
                    $results += New-HydrationResult -Name $policy.Name -Type 'CISBaselinePolicy' -Action 'WouldDelete' -Status 'DryRun'
                }
            }
            return $results
        }

        $results += Invoke-GraphBatchOperation -Items $policiesToDelete -Operation 'DELETE' -ResultType 'CISBaselinePolicy'

        return $results
    }

    # Collect all JSON files from category folders (flat structure: category/policy.json)
    $categoryFolders = Get-ChildItem -Path $BaselinePath -Directory | Where-Object {
        $_.Name -notmatch '^\.'
    }

    # Collect all policies with their metadata
    $allPolicies = @()
    foreach ($categoryFolder in $categoryFolders) {
        $jsonFiles = Get-ChildItem -Path $categoryFolder.FullName -Filter "*.json" -File -Recurse
        foreach ($jsonFile in $jsonFiles) {
            $allPolicies += @{
                File     = $jsonFile
                Category = $categoryFolder.Name
            }
        }
    }

    $totalPolicies = $allPolicies.Count
    if ($totalPolicies -eq 0) {
        Write-Verbose "No CIS baseline policies found to import"
        return $results
    }

    if ($PSCmdlet.ShouldProcess("$totalPolicies policies from CIS Baselines", "Import to Intune")) {
        $logParams = @{
            Message = "Discovered $totalPolicies CIS baseline templates across $($categoryFolders.Count) folders"
            Level   = 'Info'
        }
        Write-HydrationLog @logParams

        # Pre-fetch existing policies from all unique endpoints
        $endpointPolicyCache = @{}
        $uniqueEndpoints = $odataTypeToEndpoint.Values | Sort-Object -Unique
        $cacheIndex = 0
        foreach ($cacheEndpoint in $uniqueEndpoints) {
            $cacheIndex++
            $logParams = @{
                Message = "Caching existing CIS policies ($cacheIndex/$($uniqueEndpoints.Count)): $cacheEndpoint"
                Level   = 'Info'
            }
            Write-HydrationLog @logParams
            $endpointPolicyCache[$cacheEndpoint] = @{}
            try {
                Get-GraphPagedResults -Uri "beta/$cacheEndpoint" -ProcessItems {
                    param($items)
                    foreach ($policy in $items) {
                        $policyDisplayName = if ($cacheEndpoint -eq 'deviceManagement/configurationPolicies') {
                            $policy.name
                        } else {
                            if ($policy.displayName) { $policy.displayName } elseif ($policy.name) { $policy.name } else { $null }
                        }
                        if ($policyDisplayName -and -not $endpointPolicyCache[$cacheEndpoint].ContainsKey($policyDisplayName)) {
                            $endpointPolicyCache[$cacheEndpoint][$policyDisplayName] = @{
                                Id = $policy.id
                            }
                        }
                    }
                }
            } catch {
                Write-Verbose "Could not cache policies from $cacheEndpoint - will check individually"
            }
        }

        $logParams = @{
            Message = 'Caching complete. Preparing CIS baseline payloads...'
            Level   = 'Info'
        }
        Write-HydrationLog @logParams

        $policiesToCreate = @()

        function Update-CISSecretSettingValues {
            param(
                [Parameter(Mandatory)]
                [object]$Node
            )

            if ($null -eq $Node) {
                return
            }

            $hasProperties = $Node.PSObject -and $Node.PSObject.Properties
            if (-not $hasProperties) {
                return
            }

            if ($Node.PSObject.Properties['settingDefinitionId'] -and $Node.PSObject.Properties['simpleSettingValue']) {
                $settingDefinitionId = [string]$Node.settingDefinitionId
                $settingName = ($settingDefinitionId -split '[_-]')[-1]
                $simpleSettingValue = $Node.simpleSettingValue

                if ($simpleSettingValue -and
                    $simpleSettingValue.PSObject.Properties['@odata.type'] -and
                    $simpleSettingValue.'@odata.type' -eq '#microsoft.graph.deviceManagementConfigurationStringSettingValue' -and
                    $settingName -match '(?i)(password|secret|credential)s?$') {
                    $simpleSettingValue.'@odata.type' = '#microsoft.graph.deviceManagementConfigurationSecretSettingValue'
                    if ($simpleSettingValue.PSObject.Properties['valueState']) {
                        $simpleSettingValue.valueState = 'notEncrypted'
                    } else {
                        $simpleSettingValue | Add-Member -MemberType NoteProperty -Name valueState -Value 'notEncrypted'
                    }
                }
            }

            foreach ($property in $Node.PSObject.Properties) {
                $value = $property.Value
                if ($null -eq $value -or $value -is [string]) {
                    continue
                }

                if ($value -is [System.Collections.IEnumerable]) {
                    foreach ($item in $value) {
                        Update-CISSecretSettingValues -Node $item
                    }
                    continue
                }

                Update-CISSecretSettingValues -Node $value
            }
        }

        foreach ($policyEntry in $allPolicies) {
            $jsonFile = $policyEntry.File
            $category = $policyEntry.Category
            $policyName = [System.IO.Path]::GetFileNameWithoutExtension($jsonFile.Name)

            try {
                $jsonContent = Get-Content -Path $jsonFile.FullName -Raw
                $policyContent = $jsonContent | ConvertFrom-Json
                $odataType = $policyContent.'@odata.type'
                $odataContext = $policyContent.'@odata.context'

                # Some exported templates omit @odata.type but still include enough metadata to infer the endpoint.
                $typeEndpoint = $null
                if ($odataType -and $odataTypeToEndpoint.ContainsKey($odataType)) {
                    $typeEndpoint = $odataTypeToEndpoint[$odataType]
                } elseif ($odataContext) {
                    foreach ($contextFragment in $odataContextToEndpoint.Keys) {
                        if ($odataContext -like "*$contextFragment*") {
                            $typeEndpoint = $odataContextToEndpoint[$contextFragment]
                            break
                        }
                    }
                } elseif ($policyContent.PSObject.Properties['settings'] -and $policyContent.PSObject.Properties['platforms'] -and $policyContent.PSObject.Properties['technologies']) {
                    $typeEndpoint = 'deviceManagement/configurationPolicies'
                }

                if (-not $typeEndpoint) {
                    $unsupportedType = if ($odataType) { $odataType } else { '<missing>' }
                    Write-Verbose "  Skipping $policyName - unsupported @odata.type: $unsupportedType"
                    $results += New-HydrationResult -Name $policyName -Path $jsonFile.FullName -Type "CISBaseline/$category" -Action 'Skipped' -Status "Unsupported @odata.type: $unsupportedType"
                    continue
                }

                # Platform filtering based on JSON platforms property
                if ($Platform -and $Platform -notcontains 'All') {
                    $policyPlatform = $policyContent.platforms
                    if ($policyPlatform) {
                        $mappedPlatform = $platformValueMapping[$policyPlatform]
                        if ($mappedPlatform -and $mappedPlatform -notin $Platform) {
                            Write-Verbose "  Skipping $policyName - platform '$policyPlatform' not in filter"
                            continue
                        }
                    }
                }

                # Get display name with import prefix
                $displayName = if ($policyContent.displayName) {
                    "$($script:ImportPrefix)$($policyContent.displayName)"
                } elseif ($policyContent.name) {
                    "$($script:ImportPrefix)$($policyContent.name)"
                } else {
                    "$($script:ImportPrefix)$policyName"
                }

                # Check if policy exists using pre-fetched cache
                $unprefixedName = if ($policyContent.displayName) { $policyContent.displayName } elseif ($policyContent.name) { $policyContent.name } else { $policyName }
                $lookupNames = @($displayName)
                if ($unprefixedName -ne $displayName) {
                    $lookupNames += $unprefixedName
                }

                $matchedName = $lookupNames | Where-Object { $endpointPolicyCache[$typeEndpoint].ContainsKey($_) } | Select-Object -First 1
                $existingPolicy = if ($matchedName) { $endpointPolicyCache[$typeEndpoint][$matchedName] } else { $null }

                if ($existingPolicy -and $ImportMode -eq 'SkipIfExists') {
                    $alreadyExists = $true
                    $verifyUri = "beta/$typeEndpoint/$($existingPolicy.Id)"

                    try {
                        $null = Invoke-MgGraphRequest -Method GET -Uri $verifyUri -ErrorAction Stop
                    } catch {
                        if ($_.Exception.Message -match '404|NotFound') {
                            Write-Verbose "Policy '$matchedName' returned 404 on verify - stale data, will create"
                            $alreadyExists = $false
                            $null = $endpointPolicyCache[$typeEndpoint].Remove($matchedName)
                        } else {
                            throw
                        }
                    }

                    if ($alreadyExists) {
                        Write-HydrationLog -Message "  Skipped: $displayName" -Level Info
                        $results += New-HydrationResult -Name $displayName -Path $jsonFile.FullName -Type "CISBaseline/$category" -Action 'Skipped' -Status 'Already exists'
                        continue
                    }
                }

                # Prepare import body
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

                if ($typeEndpoint -eq 'deviceManagement/groupPolicyConfigurations' -and $importBody.PSObject.Properties['definitionValues']) {
                    $importBody.definitionValues = @($importBody.definitionValues)
                    foreach ($definitionValue in $importBody.definitionValues) {
                        if ($definitionValue -and $definitionValue.PSObject.Properties['presentationValues']) {
                            $definitionValue.presentationValues = @($definitionValue.presentationValues)
                        }
                    }
                }

                # Remove @odata metadata and action properties except @odata.type
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

                # Settings Catalog policies need special clean body construction
                if ($typeEndpoint -eq 'deviceManagement/configurationPolicies') {
                    $cleanBody = @{
                        name         = $importBody.name
                        description  = $importBody.description
                        platforms    = $importBody.platforms
                        technologies = $importBody.technologies
                        settings     = @()
                    }

                    if ($importBody.roleScopeTagIds) {
                        $cleanBody.roleScopeTagIds = $importBody.roleScopeTagIds
                    }
                    if ($importBody.templateReference -and $importBody.templateReference.templateId) {
                        $cleanBody.templateReference = @{
                            templateId = $importBody.templateReference.templateId
                        }
                    }

                    if ($importBody.settings) {
                        foreach ($setting in $importBody.settings) {
                            $cleanSetting = $setting | ConvertTo-Json -Depth 100 -Compress | ConvertFrom-Json

                            $propsToRemove = @($cleanSetting.PSObject.Properties | Where-Object {
                                    $_.Name -eq 'id' -or $_.Name -match '@odata\.' -or $_.Name -eq 'settingDefinitions'
                                })
                            foreach ($prop in $propsToRemove) {
                                $cleanSetting.PSObject.Properties.Remove($prop.Name)
                            }

                            Update-CISSecretSettingValues -Node $cleanSetting
                            $cleanBody.settings += $cleanSetting
                        }
                    }

                    $importBody = [PSCustomObject]$cleanBody
                }

                # Compliance policies: clean scheduledActionsForRule
                if ($importBody.scheduledActionsForRule) {
                    $cleanedActions = @()
                    foreach ($action in $importBody.scheduledActionsForRule) {
                        $cleanAction = @{
                            ruleName = $action.ruleName
                        }
                        if ($action.scheduledActionConfigurations) {
                            $cleanConfigs = @()
                            foreach ($config in $action.scheduledActionConfigurations) {
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

                $policiesToCreate += @{
                    Name     = $displayName
                    Path     = $jsonFile.FullName
                    Type     = "CISBaseline/$category"
                    Url      = "/$typeEndpoint"
                    BodyJson = ($importBody | ConvertTo-Json -Depth 100 -Compress)
                }
            } catch {
                $errorMsg = Get-GraphErrorMessage -ErrorRecord $_
                Write-HydrationLog -Message "  Failed to prepare: $policyName - $errorMsg" -Level Warning
                $results += New-HydrationResult -Name $policyName -Path $jsonFile.FullName -Type "CISBaseline/$category" -Action 'Failed' -Status "Prepare error: $errorMsg"
            }
        }

        # Batch create all collected policies
        if ($policiesToCreate.Count -gt 0) {
            $logParams = @{
                Message = "Prepared $($policiesToCreate.Count) CIS baseline payloads. Starting batch import..."
                Level   = 'Info'
            }
            Write-HydrationLog @logParams
            $results += Invoke-GraphBatchOperation -Items $policiesToCreate -Operation 'POST' -ResultType 'CISBaselinePolicy'
        }

    } else {
        # WhatIf mode
        foreach ($policyEntry in $allPolicies) {
            $jsonFile = $policyEntry.File
            $category = $policyEntry.Category
            $policyName = [System.IO.Path]::GetFileNameWithoutExtension($jsonFile.Name)

            # Platform filtering in WhatIf mode
            if ($Platform -and $Platform -notcontains 'All') {
                try {
                    $policyContent = Get-Content -Path $jsonFile.FullName -Raw | ConvertFrom-Json
                    $policyPlatform = $policyContent.platforms
                    if ($policyPlatform) {
                        $mappedPlatform = $platformValueMapping[$policyPlatform]
                        if ($mappedPlatform -and $mappedPlatform -notin $Platform) {
                            continue
                        }
                    }
                } catch {
                    # If we can't read the file, include it in WhatIf output
                }
            }

            $results += New-HydrationResult -Name "$($script:ImportPrefix)$policyName" -Path $jsonFile.FullName -Type "CISBaseline/$category" -Action 'WouldCreate' -Status 'DryRun'
        }
    }

    return $results
}
