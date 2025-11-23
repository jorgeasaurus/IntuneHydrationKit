function Import-IntuneCompliancePolicy {
    <#
    .SYNOPSIS
        Imports device compliance policies from templates
    .DESCRIPTION
        Reads JSON templates from Templates/Compliance and creates compliance policies via Graph.
    .PARAMETER TemplatePath
        Path to the compliance template directory (defaults to Templates/Compliance)
    .EXAMPLE
        Import-IntuneCompliancePolicy
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
        $TemplatePath = Join-Path -Path $script:TemplatesPath -ChildPath "Compliance"
    }

    if (-not (Test-Path -Path $TemplatePath)) {
        Write-Warning "Compliance template directory not found: $TemplatePath"
        return @()
    }

    $templateFiles = Get-ChildItem -Path $TemplatePath -Filter "*.json" -File -Recurse

    # Test mode - only process first template
    if ($TestMode -and $templateFiles.Count -gt 0) {
        $templateFiles = $templateFiles | Select-Object -First 1
        Write-Information "Test mode: Processing only first template: $($templateFiles.Name)" -InformationAction Continue
    }
    if (-not $templateFiles -or $templateFiles.Count -eq 0) {
        Write-Warning "No compliance templates found in: $TemplatePath"
        return @()
    }

    # Prefetch existing compliance policies (paged) from both classic and linux endpoints
    $existingByName = @{}
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
                    if ($policyName -and -not $existingByName.ContainsKey($policyName)) {
                        $existingByName[$policyName] = $policy.id
                    }
                }
                $listUri = $existingResponse.'@odata.nextLink'
            } while ($listUri)
        }
        catch {
            continue
        }
    }

    $results = @()

    # Remove existing policies if requested - ONLY policies that match template names
    if ($RemoveExisting) {
        # Get template names to know what we manage
        $templateNames = @()
        foreach ($templateFile in $templateFiles) {
            $template = Get-Content -Path $templateFile.FullName -Raw | ConvertFrom-Json
            if ($template.displayName) {
                $templateNames += $template.displayName
            }
        }

        # Only delete policies that match our templates
        $policiesToRemove = $existingByName.Keys | Where-Object { $_ -in $templateNames }

        if ($policiesToRemove.Count -gt 0) {
            Write-Information "Removing $($policiesToRemove.Count) managed compliance policies..." -InformationAction Continue
        }
        else {
            Write-Information "No managed compliance policies found to delete" -InformationAction Continue
            $summary = Get-ResultSummary -Results $results
            return $results
        }

        foreach ($policyName in $policiesToRemove) {
            $policyId = $existingByName[$policyName]

            # Determine endpoint - try deviceCompliancePolicies first, then compliancePolicies
            $deleteEndpoint = "beta/deviceManagement/deviceCompliancePolicies/$policyId"

            if ($PSCmdlet.ShouldProcess($policyName, "Delete compliance policy")) {
                try {
                    Invoke-MgGraphRequest -Method DELETE -Uri $deleteEndpoint -ErrorAction Stop
                    Write-Information "Deleted compliance policy: $policyName (ID: $policyId)" -InformationAction Continue
                    $results += New-HydrationResult -Name $policyName -Type 'CompliancePolicy' -Action 'Deleted' -Status 'Success'
                }
                catch {
                    # Try Linux endpoint if classic fails
                    try {
                        $deleteEndpoint = "beta/deviceManagement/compliancePolicies/$policyId"
                        Invoke-MgGraphRequest -Method DELETE -Uri $deleteEndpoint -ErrorAction Stop
                        Write-Information "Deleted compliance policy: $policyName (ID: $policyId)" -InformationAction Continue
                        $results += New-HydrationResult -Name $policyName -Type 'CompliancePolicy' -Action 'Deleted' -Status 'Success'
                    }
                    catch {
                        $errMessage = Get-GraphErrorMessage -ErrorRecord $_
                        Write-Warning "Failed to delete compliance policy '$policyName': $errMessage"
                        $results += New-HydrationResult -Name $policyName -Type 'CompliancePolicy' -Action 'Failed' -Status "Delete failed: $errMessage"
                    }
                }
            }
            else {
                $results += New-HydrationResult -Name $policyName -Type 'CompliancePolicy' -Action 'WouldDelete' -Status 'DryRun'
            }
        }

        # RemoveExisting mode - only delete, don't create
        $summary = Get-ResultSummary -Results $results
        Write-Information "Compliance removal complete: $($summary.Deleted) deleted, $($summary.Failed) failed" -InformationAction Continue
        return $results
    }

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
                "beta/deviceManagement/compliancePolicies"
            } else {
                "beta/deviceManagement/deviceCompliancePolicies"
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
                if (-not $Force) {
                    Write-Information "  Skipped: $displayName (already exists)" -InformationAction Continue
                    $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'CompliancePolicy' -Action 'Skipped' -Status 'Already exists'
                    continue
                }

                # Force is enabled - delete existing policy first, then recreate
                $existingId = $existingByName[$displayName]
                if ($PSCmdlet.ShouldProcess($displayName, "Delete existing compliance policy for upgrade")) {
                    try {
                        Invoke-MgGraphRequest -Method DELETE -Uri "$endpoint/$existingId" -ErrorAction Stop
                        Write-Information "Deleted existing compliance policy: $displayName (ID: $existingId)" -InformationAction Continue
                    }
                    catch {
                        $errMessage = Get-GraphErrorMessage -ErrorRecord $_
                        Write-Warning "Failed to delete existing compliance policy '$displayName': $errMessage"
                        $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'CompliancePolicy' -Action 'Failed' -Status "Delete failed: $errMessage"
                        continue
                    }
                }
                else {
                    $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'CompliancePolicy' -Action 'WouldUpdate' -Status 'DryRun'
                    continue
                }
            }

            $importBody = [Management.Automation.PSSerializer]::Deserialize(
                [Management.Automation.PSSerializer]::Serialize($template)
            )
            $propsToRemove = @('id', 'createdDateTime', 'lastModifiedDateTime', '@odata.context', 'version')
            foreach ($prop in $propsToRemove) {
                if ($importBody.PSObject.Properties[$prop]) {
                    $importBody.PSObject.Properties.Remove($prop)
                }
            }

            # Add hydration kit tag to description
            $existingDesc = if ($importBody.description) { $importBody.description } else { "" }
            $importBody.description = if ($existingDesc) { "$existingDesc - Imported by Intune-Hydration-Kit" } else { "Imported by Intune-Hydration-Kit" }

            # Linux endpoint expects 'name' instead of displayName; ensure it's present
            if ($isLinuxCompliance) {
                if (-not $importBody.name) {
                    $importBody | Add-Member -MemberType NoteProperty -Name name -Value $displayName -Force
                }
                # Some exports include displayName; keep it but ensure name is set
            }

            # Handle custom compliance policies with deviceCompliancePolicyScript
            # Uses the same approach as create-custom-compliance-policy.ps1
            if ($importBody.deviceCompliancePolicyScript) {
                $scriptDefinition = $template.deviceCompliancePolicyScriptDefinition
                $scriptDisplayName = if ($scriptDefinition.displayName) { $scriptDefinition.displayName } else { "$displayName Script" }

                # Step 1: Check if compliance script already exists or create it
                $scriptId = $null
                try {
                    $existingScripts = Invoke-MgGraphRequest -Method GET -Uri "beta/deviceManagement/deviceComplianceScripts" -ErrorAction Stop
                    $existingScript = $existingScripts.value | Where-Object { $_.displayName -eq $scriptDisplayName }

                    if ($existingScript) {
                        $scriptId = $existingScript.id
                        Write-Information "Using existing compliance script: $scriptDisplayName (ID: $scriptId)" -InformationAction Continue
                    }
                    elseif ($scriptDefinition -and $scriptDefinition.detectionScriptContentBase64) {
                        # Create the compliance script
                        $scriptBody = @{
                            description = if ($scriptDefinition.description) { $scriptDefinition.description } else { "" }
                            detectionScriptContent = $scriptDefinition.detectionScriptContentBase64
                            displayName = $scriptDisplayName
                            enforceSignatureCheck = [bool]$scriptDefinition.enforceSignatureCheck
                            publisher = if ($scriptDefinition.publisher) { $scriptDefinition.publisher } else { "Publisher" }
                            runAs32Bit = [bool]$scriptDefinition.runAs32Bit
                            runAsAccount = if ($scriptDefinition.runAsAccount) { $scriptDefinition.runAsAccount } else { "system" }
                        }

                        $newScript = Invoke-MgGraphRequest -Method POST -Uri "beta/deviceManagement/deviceComplianceScripts" -Body ($scriptBody | ConvertTo-Json -Depth 10) -ContentType "application/json" -ErrorAction Stop
                        $scriptId = $newScript.id
                        Write-Information "Created compliance script: $scriptDisplayName (ID: $scriptId)" -InformationAction Continue
                    }
                    else {
                        Write-Warning "Skipping compliance policy '$displayName' - no script definition found with detectionScriptContentBase64"
                        $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'CompliancePolicy' -Action 'Failed' -Status 'Missing detectionScriptContentBase64 in deviceCompliancePolicyScriptDefinition'
                        continue
                    }
                }
                catch {
                    Write-Warning "Failed to create/find compliance script for '$displayName': $($_.Exception.Message)"
                    $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'CompliancePolicy' -Action 'Failed' -Status "Script error: $($_.Exception.Message)"
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
                    rulesContent = $rulesBase64
                }
            }

            # Remove internal helper definition before sending
            if ($importBody.PSObject.Properties['deviceCompliancePolicyScriptDefinition']) {
                $importBody.PSObject.Properties.Remove('deviceCompliancePolicyScriptDefinition') | Out-Null
            }

            if ($PSCmdlet.ShouldProcess($displayName, "Create compliance policy")) {
                $response = Invoke-MgGraphRequest -Method POST -Uri $endpoint -Body ($importBody | ConvertTo-Json -Depth 100) -ContentType 'application/json' -ErrorAction Stop
                $action = if ($alreadyExists) { 'Updated' } else { 'Created' }
                Write-Information "  $action : $displayName" -InformationAction Continue
                $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'CompliancePolicy' -Action $action -Status 'Success'
            }
            else {
                $action = if ($alreadyExists) { 'WouldUpdate' } else { 'WouldCreate' }
                $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'CompliancePolicy' -Action $action -Status 'DryRun'
            }
        }
        catch {
            $errMessage = Get-GraphErrorMessage -ErrorRecord $_
            Write-Warning "Failed to import compliance policy from $($templateFile.FullName): $errMessage"
            $results += New-HydrationResult -Name $templateFile.Name -Path $templateFile.FullName -Type 'CompliancePolicy' -Action 'Failed' -Status $errMessage
        }
    }

    $summary = Get-ResultSummary -Results $results

    Write-Information "Compliance import complete: $($summary.Created) created, $($summary.Skipped) skipped, $($summary.Failed) failed" -InformationAction Continue

    return $results
}