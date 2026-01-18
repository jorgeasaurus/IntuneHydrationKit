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
    $endpointsToList = @(
        "beta/deviceManagement/deviceCompliancePolicies",
        "beta/deviceManagement/compliancePolicies"
    )
    foreach ($listUriStart in $endpointsToList) {
        $listUri = $listUriStart
        try {
            do {
                $existingResponse = Invoke-MgGraphRequest -Method GET -Uri $listUri -ErrorAction Stop
                foreach ($policy in $existingResponse.value) {
                    $policyName = if ($policy.displayName) { $policy.displayName } elseif ($policy.name) { $policy.name } else { $null }
                    if ($policyName -and -not $existingPolicies.ContainsKey($policyName)) {
                        $existingPolicies[$policyName] = @{
                            Id          = $policy.id
                            Description = $policy.description
                            Endpoint    = $listUriStart
                        }
                    }
                }
                $listUri = $existingResponse.'@odata.nextLink'
            } while ($listUri)
        } catch {
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
        $maxBatchSize = if ($script:MaxBatchSize) { $script:MaxBatchSize } else { 10 }
        $maxRetries = 3
        $retryDelaySeconds = 2

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
                Name     = $policyName
                Id       = $policyInfo.Id
                Endpoint = $policyInfo.Endpoint
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

        # Batch delete policies with retry logic
        Write-Verbose "Deleting $($policiesToDelete.Count) compliance policies in batches..."
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
                            $results += New-HydrationResult -Name $policy.Name -Type 'CompliancePolicy' -Action 'Deleted' -Status 'Success'
                        } elseif ($resp.status -eq 404) {
                            Write-HydrationLog -Message "  Skipped: $($policy.Name) (already deleted)" -Level Info
                            $results += New-HydrationResult -Name $policy.Name -Type 'CompliancePolicy' -Action 'Skipped' -Status 'Already deleted'
                        } elseif ($resp.status -ge 500 -and $retryCount -lt $maxRetries) {
                            Write-Verbose "Server error ($($resp.status)) for '$($policy.Name)' - will retry"
                            $itemsToRetry += $policy
                        } else {
                            $errorMessage = if ($resp.body.error.message) { $resp.body.error.message } else { "HTTP $($resp.status)" }
                            Write-HydrationLog -Message "  [!] Failed: $($policy.Name) - $errorMessage" -Level Warning
                            $results += New-HydrationResult -Name $policy.Name -Type 'CompliancePolicy' -Action 'Failed' -Status "Delete failed: $errorMessage"
                        }
                    }
                } catch {
                    if ($retryCount -lt $maxRetries) {
                        Write-Verbose "Batch delete failed, will retry: $_"
                        $itemsToRetry = $pendingItems
                    } else {
                        Write-Warning "Batch delete failed: $_"
                        foreach ($policy in $pendingItems) {
                            $results += New-HydrationResult -Name $policy.Name -Type 'CompliancePolicy' -Action 'Failed' -Status "Batch delete failed: $_"
                        }
                    }
                }

                $pendingItems = $itemsToRetry
                $retryCount++
            }
        }

        return $results
    }

    # Batch settings
    $maxBatchSize = if ($script:MaxBatchSize) { $script:MaxBatchSize } else { 10 }
    $maxRetries = 3
    $retryDelaySeconds = 2

    # Collect policies to create - separate standard and custom (with scripts)
    $standardPoliciesToCreate = @()
    $customPoliciesToCreate = @()

    foreach ($templateFile in $templateFiles) {
        try {
            $template = Get-Content -Path $templateFile.FullName -Raw -Encoding utf8 | ConvertFrom-Json
            $displayName = $template.displayName
            if (-not $displayName) {
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

            # For Linux, also consider 'name' when matching
            $lookupNames = @($displayName)
            if ($isLinuxCompliance -and $template.name) {
                $lookupNames += $template.name
            }

            $alreadyExists = $false
            foreach ($ln in $lookupNames) {
                if ($existingByName.ContainsKey($ln)) {
                    $alreadyExists = $true
                    break
                }
            }

            if ($alreadyExists) {
                Write-HydrationLog -Message "  Skipped: $displayName" -Level Info
                $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'CompliancePolicy' -Action 'Skipped' -Status 'Already exists'
                continue
            }

            $importBody = Copy-DeepObject -InputObject $template
            Remove-ReadOnlyGraphProperties -InputObject $importBody

            # Add hydration kit tag to description
            $existingDesc = if ($importBody.description) { $importBody.description } else { "" }
            $importBody.description = if ($existingDesc) { "$existingDesc - Imported by Intune Hydration Kit" } else { "Imported by Intune Hydration Kit" }

            # Linux endpoint expects 'name' instead of displayName; ensure it's present
            if ($isLinuxCompliance) {
                if (-not $importBody.name) {
                    $importBody | Add-Member -MemberType NoteProperty -Name name -Value $displayName -Force
                }
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
                    Endpoint = $endpoint
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

    # Batch create standard policies with retry logic
    if ($standardPoliciesToCreate.Count -gt 0) {
        Write-Verbose "Creating $($standardPoliciesToCreate.Count) standard compliance policies in batches..."

        for ($batchStart = 0; $batchStart -lt $standardPoliciesToCreate.Count; $batchStart += $maxBatchSize) {
            $batchEnd = [Math]::Min($batchStart + $maxBatchSize, $standardPoliciesToCreate.Count) - 1
            $currentBatch = $standardPoliciesToCreate[$batchStart..$batchEnd]

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
                            $results += New-HydrationResult -Name $policy.Name -Path $policy.Path -Type 'CompliancePolicy' -Action 'Created' -Status 'Success'
                        } elseif ($resp.status -eq 409) {
                            Write-HydrationLog -Message "  Skipped: $($policy.Name) (race condition)" -Level Info
                            $results += New-HydrationResult -Name $policy.Name -Path $policy.Path -Type 'CompliancePolicy' -Action 'Skipped' -Status 'Already exists (race condition)'
                        } elseif ($resp.status -ge 500 -and $retryCount -lt $maxRetries) {
                            Write-Verbose "Server error ($($resp.status)) for '$($policy.Name)' - will retry"
                            $itemsToRetry += $policy
                        } else {
                            $errorMessage = if ($resp.body.error.message) { $resp.body.error.message } else { "HTTP $($resp.status)" }
                            Write-HydrationLog -Message "  [!] Failed: $($policy.Name) - $errorMessage" -Level Warning
                            $results += New-HydrationResult -Name $policy.Name -Path $policy.Path -Type 'CompliancePolicy' -Action 'Failed' -Status $errorMessage
                        }
                    }
                } catch {
                    if ($retryCount -lt $maxRetries) {
                        Write-Verbose "Batch create failed, will retry: $_"
                        $itemsToRetry = $pendingItems
                    } else {
                        Write-Warning "Batch create failed: $_"
                        foreach ($policy in $pendingItems) {
                            $results += New-HydrationResult -Name $policy.Name -Path $policy.Path -Type 'CompliancePolicy' -Action 'Failed' -Status "Batch create failed: $_"
                        }
                    }
                }

                $pendingItems = $itemsToRetry
                $retryCount++
            }
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
            $existingScripts = Invoke-MgGraphRequest -Method GET -Uri "beta/deviceManagement/deviceComplianceScripts" -ErrorAction Stop
            $existingScript = $existingScripts.value | Where-Object { $_.displayName -eq $scriptDisplayName }

            if ($existingScript) {
                $scriptId = $existingScript.id
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