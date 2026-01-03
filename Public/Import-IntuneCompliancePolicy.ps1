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
        [switch]$RemoveExisting
    )

    if (-not $TemplatePath) {
        $TemplatePath = Join-Path -Path $script:TemplatesPath -ChildPath "Compliance"
    }

    if (-not (Test-Path -Path $TemplatePath)) {
        Write-Warning "Compliance template directory not found: $TemplatePath"
        return @()
    }

    $templateFiles = Get-HydrationTemplates -Path $TemplatePath -Recurse -ResourceType "compliance template"

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
                            Id = $policy.id
                            Description = $policy.description
                            Endpoint = $listUriStart
                        }
                    }
                }
                $listUri = $existingResponse.'@odata.nextLink'
            } while ($listUri)
        }
        catch {
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
    # SAFETY: Only delete policies that have "Imported by Intune-Hydration-Kit" in description
    if ($RemoveExisting) {
        foreach ($policyName in $existingPolicies.Keys) {
            $policyInfo = $existingPolicies[$policyName]

            # Safety check: Only delete if created by this kit (has hydration marker in description)
            if (-not (Test-HydrationKitObject -Description $policyInfo.Description -ObjectName $policyName)) {
                Write-Verbose "Skipping '$policyName' - not created by Intune-Hydration-Kit"
                continue
            }

            # Determine endpoint based on where we found the policy
            $deleteEndpoint = "$($policyInfo.Endpoint)/$($policyInfo.Id)"

            if ($PSCmdlet.ShouldProcess($policyName, "Delete compliance policy")) {
                try {
                    Invoke-MgGraphRequest -Method DELETE -Uri $deleteEndpoint -ErrorAction Stop
                    Write-HydrationLog -Message "  Deleted: $policyName" -Level Info
                    $results += New-HydrationResult -Name $policyName -Type 'CompliancePolicy' -Action 'Deleted' -Status 'Success'
                }
                catch {
                    $errMessage = Get-GraphErrorMessage -ErrorRecord $_
                    Write-HydrationLog -Message "  Failed: $policyName - $errMessage" -Level Warning
                    $results += New-HydrationResult -Name $policyName -Type 'CompliancePolicy' -Action 'Failed' -Status "Delete failed: $errMessage"
                }
            }
            else {
                Write-HydrationLog -Message "  WouldDelete: $policyName" -Level Info
                $results += New-HydrationResult -Name $policyName -Type 'CompliancePolicy' -Action 'WouldDelete' -Status 'DryRun'
            }
        }

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
                Write-HydrationLog -Message "  Skipped: $displayName" -Level Info
                $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'CompliancePolicy' -Action 'Skipped' -Status 'Already exists'
                continue
            }

            $importBody = Copy-DeepObject -InputObject $template
            Remove-ReadOnlyGraphProperties -InputObject $importBody

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
                $null = $importBody.PSObject.Properties.Remove('deviceCompliancePolicyScriptDefinition')
            }

            if ($PSCmdlet.ShouldProcess($displayName, "Create compliance policy")) {
                $null = Invoke-MgGraphRequest -Method POST -Uri $endpoint -Body ($importBody | ConvertTo-Json -Depth 100) -ContentType 'application/json' -ErrorAction Stop
                Write-HydrationLog -Message "  Created: $displayName" -Level Info
                $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'CompliancePolicy' -Action 'Created' -Status 'Success'
            }
            else {
                Write-HydrationLog -Message "  WouldCreate: $displayName" -Level Info
                $results += New-HydrationResult -Name $displayName -Path $templateFile.FullName -Type 'CompliancePolicy' -Action 'WouldCreate' -Status 'DryRun'
            }
        }
        catch {
            $errMessage = Get-GraphErrorMessage -ErrorRecord $_
            Write-HydrationLog -Message "  Failed: $($templateFile.Name) - $errMessage" -Level Warning
            $results += New-HydrationResult -Name $templateFile.Name -Path $templateFile.FullName -Type 'CompliancePolicy' -Action 'Failed' -Status $errMessage
        }
    }

    return $results
}