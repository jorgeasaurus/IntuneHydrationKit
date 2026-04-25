function Import-IntuneCompliancePolicy {
    <#
    .SYNOPSIS
        Imports device compliance policies from templates
    .DESCRIPTION
        Reads JSON templates from Templates/Compliance and creates compliance policies via Graph.
    .PARAMETER TemplatePath
        Path to the compliance template directory (defaults to Templates/Compliance)
    .PARAMETER Platform
        Filter templates by platform. Valid values: Windows, macOS, iOS, Android, Linux, All.
        Defaults to 'All' which imports all compliance templates regardless of platform.
    .EXAMPLE
        Import-IntuneCompliancePolicy
    .EXAMPLE
        Import-IntuneCompliancePolicy -Platform Windows,macOS
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [string]$TemplatePath,

        [Parameter()]
        [ValidateSet('Windows', 'macOS', 'iOS', 'Android', 'Linux', 'All')]
        [string[]]$Platform = @('All'),

        [Parameter()]
        [switch]$RemoveExisting
    )

    if (-not $TemplatePath) {
        $TemplatePath = Join-Path -Path $script:TemplatesPath -ChildPath "Compliance"
    }

    if (-not (Test-Path -Path $TemplatePath)) {
        Write-Warning "Compliance template directory not found: $TemplatePath"
        return @()
    }

    $templateFiles = Get-FilteredTemplates -Path $TemplatePath -Platform $Platform -FilterMode 'Prefix' -Recurse -ResourceType "compliance template"

    if (-not $templateFiles -or $templateFiles.Count -eq 0) {
        Write-Warning "No compliance templates found in: $TemplatePath"
        return @()
    }

    # Prefetch existing compliance policies (paged) from both classic and linux endpoints
    # Store full policy objects so we can check descriptions later
    $existingPolicies = @{}
    # Each endpoint has different property names - use endpoint-specific $select
    $endpointsToList = @(
        @{ Uri = "beta/deviceManagement/deviceCompliancePolicies"; Select = "id,displayName,description" },
        @{ Uri = "beta/deviceManagement/compliancePolicies"; Select = "id,name,description" }
    )
    foreach ($ep in $endpointsToList) {
        $listUri = "$($ep.Uri)`?`$select=$($ep.Select)"
        try {
            do {
                $existingResponse = Invoke-MgGraphRequest -Method GET -Uri $listUri -ErrorAction Stop
                foreach ($policy in $existingResponse.value) {
                    $policyName = if ($policy.displayName) { $policy.displayName } elseif ($policy.name) { $policy.name } else { $null }
                    if ($policyName) {
                        $isTagged = Test-HydrationKitObject -Description $policy.description
                        if (-not $existingPolicies.ContainsKey($policyName)) {
                            $existingPolicies[$policyName] = @{
                                Id          = $policy.id
                                Description = $policy.description
                                Endpoint    = $ep.Uri
                                IsTagged    = $isTagged
                            }
                        } elseif ($isTagged -and -not $existingPolicies[$policyName].IsTagged) {
                            $existingPolicies[$policyName] = @{
                                Id          = $policy.id
                                Description = $policy.description
                                Endpoint    = $ep.Uri
                                IsTagged    = $true
                            }
                        }
                    }
                }
                $listUri = $existingResponse.'@odata.nextLink'
            } while ($listUri)
        } catch {
            Write-Warning "Failed to list compliance policies from $($ep.Uri): $_"
            continue
        }
    }

    # Build a simple name->id lookup for backwards compatibility in the import section
    $existingByName = @{}
    foreach ($key in $existingPolicies.Keys) {
        $existingByName[$key] = $existingPolicies[$key].Id
    }

    $results = @()

    # Remove existing policies if requested
    # SAFETY: Only delete policies that have "Imported by Intune Hydration Kit" in description
    if ($RemoveExisting) {
        # Collect policies to delete (only those with hydration marker)
        $policiesToDelete = @()
        foreach ($policyName in $existingPolicies.Keys) {
            $policyInfo = $existingPolicies[$policyName]

            # Safety check: Only delete if created by this kit (has hydration marker in description)
            if (-not (Test-HydrationKitObject -Description $policyInfo.Description -ObjectName $policyName)) {
                Write-Verbose "Skipping '$policyName' - not created by Intune Hydration Kit"
                continue
            }

            $policiesToDelete += @{
                Name = $policyName
                Id   = $policyInfo.Id
                Url  = "/$($policyInfo.Endpoint -replace '^beta/', '')/$($policyInfo.Id)"
            }
        }

        if ($policiesToDelete.Count -eq 0) {
            Write-Verbose "No compliance policies found to delete"
            return $results
        }

        # Handle WhatIf mode
        if (-not $PSCmdlet.ShouldProcess("$($policiesToDelete.Count) compliance policies", "Delete")) {
            foreach ($policy in $policiesToDelete) {
                Write-HydrationLog -Message "  WouldDelete: $($policy.Name)" -Level Info
                $results += New-HydrationResult -Name $policy.Name -Type 'CompliancePolicy' -Action 'WouldDelete' -Status 'DryRun'
            }
            return $results
        }

        # Batch delete policies using centralized helper
        $results += Invoke-GraphBatchOperation -Items $policiesToDelete -Operation 'DELETE' -ResultType 'CompliancePolicy'

        return $results
    }

    # Collect policies to create - separate standard and custom (with scripts)
    $standardPoliciesToCreate = @()
    $customPoliciesToCreate = @()

    foreach ($templateFile in $templateFiles) {
        try {
            $template = Get-Content -Path $templateFile.FullName -Raw -Encoding utf8 | ConvertFrom-Json
            $displayName = "$($script:ImportPrefix)$($template.displayName)"
            if (-not $template.displayName) {
                Write-Warning "Template missing displayName: $($templateFile.FullName)"
                $results += New-HydrationResult -Name $templateFile.Name -Path $templateFile.FullName -Type 'CompliancePolicy' -Action 'Failed' -Status 'Missing displayName'
                continue
            }

            # Choose endpoint: Linux uses compliancePolicies, others use deviceCompliancePolicies
            $isLinuxCompliance = $template.platforms -eq 'linux' -and $template.technologies -eq 'linuxMdm'
            $endpoint = if ($isLinuxCompliance) {
                "deviceManagement/compliancePolicies"
            } else {
                "deviceManagement/deviceCompliancePolicies"
            }

            # Check both prefixed and unprefixed names to avoid duplicates when upgrading from pre-prefix tenants
            $lookupNames = @($displayName)
            if ($template.displayName -and $template.displayName -ne $displayName) {
                $lookupNames += $template.displayName
            }
            if ($isLinuxCompliance -and $template.name -and $template.name -ne $template.displayName) {
                $lookupNames += $template.name
            }

            $alreadyExists = $false
            foreach ($ln in $lookupNames) {
                if ($existingPolicies.ContainsKey($ln) -and $existingPolicies[$ln].IsTagged) {
                    $alreadyExists = $true
                    break
                }
            }

            # Verify via targeted GET to guard against stale prefetch data after deletes
            if ($alreadyExists) {
                $matchedName = $lookupNames | Where-Object { $existingPolicies.ContainsKey($_) -and $existingPolicies[$_].IsTagged } | Select-Object -First 1
                $matchedPolicy = $existingPolicies[$matchedName]
                $verifyEndpoint = if ($matchedPolicy.Endpoint -match '^beta/') {
                    $matchedPolicy.Endpoint
                } else {
                    "beta/$($matchedPolicy.Endpoint)"
                }
                $verifyUri = "$verifyEndpoint/$($matchedPolicy.Id)"
                try {
                    $null = Invoke-MgGraphRequest -Method GET -Uri $verifyUri -ErrorAction Stop
                } catch {
                    if ($_.Exception.Message -match '404|NotFound') {
                        Write-Verbose "Policy '$matchedName' returned 404 on verify - stale data, will create"
                        $alreadyExists = $false
                    }
                }
            }

            if ($alreadyExists) {
                Write-HydrationLog -Message "  Skipped: $displayName" -Level Info
                $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'CompliancePolicy' -Action 'Skipped' -Status 'Already exists'
                continue
            }

            $importBody = Copy-DeepObject -InputObject $template
            Remove-ReadOnlyGraphProperties -InputObject $importBody

            # Apply import prefix to body
            if ($importBody.displayName) { $importBody.displayName = $displayName }

            # Add hydration kit tag to description
            $importBody.description = New-HydrationDescription -ExistingText $importBody.description

            # Linux endpoint expects 'name' instead of displayName; ensure it matches the prefixed name
            if ($isLinuxCompliance) {
                $importBody | Add-Member -MemberType NoteProperty -Name name -Value $displayName -Force
            }

            # Custom compliance policies with scripts need sequential processing
            if ($importBody.deviceCompliancePolicyScript) {
                $customPoliciesToCreate += @{
                    Name       = $displayName
                    Path       = $templateFile.FullName
                    Endpoint   = $endpoint
                    ImportBody = $importBody
                    Template   = $template
                }
            } else {
                # Remove internal helper definition before storing
                if ($importBody.PSObject.Properties['deviceCompliancePolicyScriptDefinition']) {
                    $null = $importBody.PSObject.Properties.Remove('deviceCompliancePolicyScriptDefinition')
                }

                # Store body as JSON string to avoid PowerShell serialization issues
                $standardPoliciesToCreate += @{
                    Name     = $displayName
                    Path     = $templateFile.FullName
                    Url      = "/$endpoint"
                    BodyJson = ($importBody | ConvertTo-Json -Depth 100 -Compress)
                }
            }
        } catch {
            $errMessage = Get-GraphErrorMessage -ErrorRecord $_
            Write-HydrationLog -Message "  Failed to prepare: $($templateFile.Name) - $errMessage" -Level Warning
            $results += New-HydrationResult -Name $templateFile.Name -Path $templateFile.FullName -Type 'CompliancePolicy' -Action 'Failed' -Status "Prepare error: $errMessage"
        }
    }

    # Handle WhatIf mode
    if (-not $PSCmdlet.ShouldProcess("$($standardPoliciesToCreate.Count + $customPoliciesToCreate.Count) compliance policies", "Create")) {
        foreach ($policy in $standardPoliciesToCreate) {
            Write-HydrationLog -Message "  WouldCreate: $($policy.Name)" -Level Info
            $results += New-HydrationResult -Name $policy.Name -Path $policy.Path -Type 'CompliancePolicy' -Action 'WouldCreate' -Status 'DryRun'
        }
        foreach ($policy in $customPoliciesToCreate) {
            Write-HydrationLog -Message "  WouldCreate: $($policy.Name)" -Level Info
            $results += New-HydrationResult -Name $policy.Name -Path $policy.Path -Type 'CompliancePolicy' -Action 'WouldCreate' -Status 'DryRun'
        }
        return $results
    }

    # Batch create standard policies using centralized helper
    if ($standardPoliciesToCreate.Count -gt 0) {
        $results += Invoke-GraphBatchOperation -Items $standardPoliciesToCreate -Operation 'POST' -ResultType 'CompliancePolicy'
    }

    $existingComplianceScripts = @{}
    if ($customPoliciesToCreate.Count -gt 0) {
        try {
            Get-GraphPagedResults -Uri "beta/deviceManagement/deviceComplianceScripts?`$select=id,displayName" -ProcessItems {
                param($items)

                foreach ($script in $items) {
                    if ($script.displayName -and -not $existingComplianceScripts.ContainsKey($script.displayName)) {
                        $existingComplianceScripts[$script.displayName] = $script.id
                    }
                }
            }
        } catch {
            Write-Warning "Failed to prefetch compliance scripts: $_"
        }
    }

    # Process custom compliance policies with scripts sequentially (require script creation first)
    foreach ($policyInfo in $customPoliciesToCreate) {
        $displayName = $policyInfo.Name
        $templateFile = @{ FullName = $policyInfo.Path }
        $importBody = $policyInfo.ImportBody
        $template = $policyInfo.Template
        $endpoint = "beta/$($policyInfo.Endpoint)"

        try {
            $scriptDefinition = $template.deviceCompliancePolicyScriptDefinition
            $scriptDisplayName = if ($scriptDefinition.displayName) { $scriptDefinition.displayName } else { "$displayName Script" }

            # Step 1: Check if compliance script already exists or create it
            $scriptId = $null
            if ($existingComplianceScripts.ContainsKey($scriptDisplayName)) {
                $scriptId = $existingComplianceScripts[$scriptDisplayName]
            } elseif ($scriptDefinition -and $scriptDefinition.detectionScriptContentBase64) {
                # Create the compliance script
                $scriptBody = @{
                    description            = if ($scriptDefinition.description) { $scriptDefinition.description } else { "" }
                    detectionScriptContent = $scriptDefinition.detectionScriptContentBase64
                    displayName            = $scriptDisplayName
                    enforceSignatureCheck  = [bool]$scriptDefinition.enforceSignatureCheck
                    publisher              = if ($scriptDefinition.publisher) { $scriptDefinition.publisher } else { "Publisher" }
                    runAs32Bit             = [bool]$scriptDefinition.runAs32Bit
                    runAsAccount           = if ($scriptDefinition.runAsAccount) { $scriptDefinition.runAsAccount } else { "system" }
                }

                $newScript = Invoke-MgGraphRequest -Method POST -Uri "beta/deviceManagement/deviceComplianceScripts" -Body ($scriptBody | ConvertTo-Json -Depth 10) -ContentType "application/json" -ErrorAction Stop
                $scriptId = $newScript.id
                $existingComplianceScripts[$scriptDisplayName] = $scriptId
            } else {
                Write-Warning "Skipping compliance policy '$displayName' - no script definition found with detectionScriptContentBase64"
                $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'CompliancePolicy' -Action 'Failed' -Status 'Missing detectionScriptContentBase64 in deviceCompliancePolicyScriptDefinition'
                continue
            }

            # Step 2: Convert rules to base64
            $rulesSource = $scriptDefinition.rules
            if (-not $rulesSource) {
                Write-Warning "Skipping compliance policy '$displayName' - no rules found in deviceCompliancePolicyScriptDefinition"
                $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'CompliancePolicy' -Action 'Failed' -Status 'Missing rules in deviceCompliancePolicyScriptDefinition'
                continue
            }

            $rulesJson = $rulesSource | ConvertTo-Json -Depth 100 -Compress
            $rulesBytes = [System.Text.Encoding]::UTF8.GetBytes($rulesJson)
            $rulesBase64 = [System.Convert]::ToBase64String($rulesBytes)

            # Step 3: Update the policy body with resolved values
            $importBody.deviceCompliancePolicyScript = @{
                deviceComplianceScriptId = $scriptId
                rulesContent             = $rulesBase64
            }

            # Remove internal helper definition before sending
            if ($importBody.PSObject.Properties['deviceCompliancePolicyScriptDefinition']) {
                $null = $importBody.PSObject.Properties.Remove('deviceCompliancePolicyScriptDefinition')
            }

            $null = Invoke-MgGraphRequest -Method POST -Uri $endpoint -Body ($importBody | ConvertTo-Json -Depth 100) -ContentType 'application/json' -ErrorAction Stop
            Write-HydrationLog -Message "  Created: $displayName" -Level Info
            $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'CompliancePolicy' -Action 'Created' -Status 'Success'
        } catch {
            $errMessage = Get-GraphErrorMessage -ErrorRecord $_
            Write-HydrationLog -Message "  Failed: $displayName - $errMessage" -Level Warning
            $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'CompliancePolicy' -Action 'Failed' -Status $errMessage
        }
    }

    return $results
}
