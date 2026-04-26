function Import-IntuneConditionalAccessPolicy {
    <#
    .SYNOPSIS
        Imports Conditional Access starter pack
    .DESCRIPTION
        Imports CA policies from templates with state forced to disabled.
        All policies are created in disabled state for safety.
    .PARAMETER TemplatePath
        Path to the CA template directory
    .PARAMETER Prefix
        Optional prefix to add to policy names
    .EXAMPLE
        Import-IntuneConditionalAccessPolicy -TemplatePath ./Templates/ConditionalAccess
    .EXAMPLE
        Import-IntuneConditionalAccessPolicy -TemplatePath ./Templates/ConditionalAccess -Prefix "Hydration - "
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [string]$TemplatePath,

        [Parameter()]
        [string]$Prefix = $script:ImportPrefix,

        [Parameter()]
        [switch]$RemoveExisting
    )

    # Use default template path if not specified
    if (-not $TemplatePath) {
        $TemplatePath = Join-Path -Path $script:TemplatesPath -ChildPath "ConditionalAccess"
    }

    if (-not (Test-Path -Path $TemplatePath)) {
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("Conditional Access template directory not found: $TemplatePath"),
            'CATemplateNotFound',
            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
            $TemplatePath
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    # Get all CA policy templates (non-recursive for CA policies)
    $templateFiles = Get-HydrationTemplates -Path $TemplatePath -ResourceType "Conditional Access template"

    if (-not $templateFiles -or $templateFiles.Count -eq 0) {
        Write-Warning "No Conditional Access templates found in: $TemplatePath"
        return @()
    }

    # Check for Premium P2 license once at the start
    $premiumP2ServicePlans = Get-PremiumP2ServicePlans

    $hasPremiumP2 = $false
    try {
        $subscribedSkus = Invoke-MgGraphRequest -Method GET -Uri "beta/subscribedSkus?`$select=id,capabilityStatus,servicePlans" -ErrorAction Stop
        foreach ($sku in $subscribedSkus.value) {
            if ($sku.capabilityStatus -ne 'Enabled') { continue }
            foreach ($plan in $sku.servicePlans) {
                if ($plan.servicePlanName -in $premiumP2ServicePlans -and $plan.provisioningStatus -eq 'Success') {
                    $hasPremiumP2 = $true
                    break
                }
            }
            if ($hasPremiumP2) { break }
        }
    } catch {
        Write-Verbose "Failed to check Premium P2 license: $_"
        $hasPremiumP2 = $true  # Allow attempt if check fails
    }

    if (-not $hasPremiumP2) {
        Write-Warning "No Azure AD Premium P2 license detected. Risk-based Conditional Access policies will be skipped."
    }

    $results = @()

    function Get-ExistingConditionalAccessPolicies {
        $policies = @{}

        try {
            Get-GraphPagedResults -Uri "beta/identity/conditionalAccess/policies?`$select=id,displayName,state" -ProcessItems {
                param($items)
                foreach ($policy in $items) {
                    if (-not $policies.ContainsKey($policy.displayName)) {
                        $policies[$policy.displayName] = @{
                            Id    = $policy.id
                            State = $policy.state
                        }
                    }
                }
            }
        } catch {
            Write-Warning "Could not retrieve existing CA policies: $_"
        }

        return $policies
    }

    $templateNameSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($templateFile in $templateFiles) {
        $policyName = "$Prefix$([System.IO.Path]::GetFileNameWithoutExtension($templateFile.Name))"
        $null = $templateNameSet.Add($policyName)
    }

    $escapedPrefix = [regex]::Escape($Prefix)

    function Test-IsTemplateManagedPolicyName {
        param(
            [Parameter(Mandatory)]
            [string]$PolicyName
        )

        if ($templateNameSet.Contains($PolicyName)) {
            return $true
        }

        $nameWithoutPrefix = $PolicyName -replace "^$escapedPrefix", ''
        return $templateNameSet.Contains("$Prefix$nameWithoutPrefix")
    }

    # Prefetch existing CA policies
    $existingPolicies = Get-ExistingConditionalAccessPolicies

    # Remove existing CA policies if requested
    # SAFETY: Conditional Access policies do not have a description field, so we identify
    # policies by matching template names. Additionally, we ONLY delete policies that are
    # in disabled state to prevent accidental deletion of enabled policies.
    if ($RemoveExisting) {
        $loggedEnabledSkips = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $completedDeleteNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $maxDeletePasses = 5

        function Get-ConditionalAccessPoliciesToDelete {
            param(
                [Parameter(Mandatory)]
                [hashtable]$CurrentPolicies
            )

            $policiesToDelete = @()
            $skipResults = @()

            foreach ($policyName in $CurrentPolicies.Keys) {
                if (-not (Test-IsTemplateManagedPolicyName -PolicyName $policyName)) {
                    continue
                }

                if ($completedDeleteNames.Contains($policyName)) {
                    continue
                }

                $policyInfo = $CurrentPolicies[$policyName]

                if ($policyInfo.State -ne 'disabled') {
                    if ($loggedEnabledSkips.Add($policyName)) {
                        Write-HydrationLog -Message "  Skipped: $policyName - policy is not disabled (state: $($policyInfo.State))" -Level Warning
                        $skipResults += New-HydrationResult -Name $policyName -Type 'ConditionalAccessPolicy' -Action 'Skipped' -Status "Not deleted: policy is $($policyInfo.State) (must be disabled)"
                    }
                    continue
                }

                $policiesToDelete += @{
                    Name = $policyName
                    Id   = $policyInfo.Id
                }
            }

            return @{
                PoliciesToDelete = @($policiesToDelete)
                SkipResults      = @($skipResults)
            }
        }

        $deleteCandidateState = Get-ConditionalAccessPoliciesToDelete -CurrentPolicies $existingPolicies
        $results += $deleteCandidateState.SkipResults
        $policiesToDelete = $deleteCandidateState.PoliciesToDelete

        if ($policiesToDelete.Count -eq 0) {
            Write-Verbose "No Conditional Access policies found to delete"
            return $results
        }

        if (-not $PSCmdlet.ShouldProcess('Conditional Access policies matching hydration templates', 'Delete')) {
            if ($WhatIfPreference) {
                foreach ($policy in $policiesToDelete) {
                    Write-HydrationLog -Message "  WouldDelete: $($policy.Name)" -Level Info
                    $results += New-HydrationResult -Name $policy.Name -Type 'ConditionalAccessPolicy' -Action 'WouldDelete' -Status 'DryRun'
                }
            }
            return $results
        }

        for ($deletePass = 0; $deletePass -lt $maxDeletePasses -and $policiesToDelete.Count -gt 0; $deletePass++) {
            $deleteResults = @(Invoke-GraphBatchOperation -Items $policiesToDelete -Operation 'DELETE' -BaseUrl '/identity/conditionalAccess/policies' -ResultType 'ConditionalAccessPolicy')
            $results += $deleteResults

            foreach ($deleteResult in $deleteResults) {
                if ($deleteResult.Name -and $deleteResult.Action -in @('Deleted', 'Skipped', 'Failed')) {
                    $null = $completedDeleteNames.Add($deleteResult.Name)
                }
            }

            if ($deletePass -eq ($maxDeletePasses - 1)) {
                break
            }

            $currentPolicies = Get-ExistingConditionalAccessPolicies
            $deleteCandidateState = Get-ConditionalAccessPoliciesToDelete -CurrentPolicies $currentPolicies
            $results += $deleteCandidateState.SkipResults
            $policiesToDelete = $deleteCandidateState.PoliciesToDelete
        }

        return $results
    }

    # Collect policies to create
    $policiesToCreate = @()
    foreach ($templateFile in $templateFiles) {
        $policyName = [System.IO.Path]::GetFileNameWithoutExtension($templateFile.Name)
        $displayName = "$Prefix$policyName"

        try {
            # Load template
            $templateContent = Get-Content -Path $templateFile.FullName -Raw -Encoding utf8
            $policy = $templateContent | ConvertFrom-Json

            # Check if policy requires P2 and tenant doesn't have it
            if (-not $hasPremiumP2 -and (Test-ConditionalAccessPolicyRequiresP2 -Policy $policy)) {
                Write-HydrationLog -Message "  Skipped: $displayName - requires Azure AD Premium P2 license (uses risk-based conditions)" -Level Warning
                $results += New-HydrationResult -Name $displayName -Type 'ConditionalAccessPolicy' -Action 'Skipped' -Status 'Requires Premium P2 license'
                continue
            }

            # Check if policy requires private preview features
            $previewFeature = Test-ConditionalAccessPolicyRequiresPreview -Policy $policy
            if ($previewFeature) {
                Write-HydrationLog -Message "  Skipped: $displayName - requires private preview feature: $previewFeature (tenant must be explicitly authorized)" -Level Warning
                $results += New-HydrationResult -Name $displayName -Type 'ConditionalAccessPolicy' -Action 'Skipped' -Status "Requires private preview: $previewFeature"
                continue
            }

            # Check if policy already exists using prefetched list
            if ($existingPolicies.ContainsKey($displayName)) {
                $existingPolicy = $existingPolicies[$displayName]
                Write-HydrationLog -Message "  Skipped: $displayName" -Level Info
                $results += New-HydrationResult -Name $displayName -Type 'ConditionalAccessPolicy' -Id $existingPolicy.Id -Action 'Skipped' -Status 'Already exists' -State $existingPolicy.State
                continue
            }

            # Build the policy body - force state to disabled
            $policyBody = @{
                displayName   = $displayName
                state         = "disabled"  # Always disabled for safety
                conditions    = $policy.conditions
                grantControls = $policy.grantControls
            }

            # Add session controls if present
            if ($policy.sessionControls) {
                $policyBody.sessionControls = $policy.sessionControls
            }

            # Remove any odata context properties that shouldn't be in create request
            $jsonBody = $policyBody | ConvertTo-Json -Depth 20 -Compress
            $jsonBody = $jsonBody -replace '"@odata\.[^"]*":\s*"[^"]*",?\s*', ''
            $jsonBody = $jsonBody -replace '"@odata\.[^"]*":\s*null,?\s*', ''

            $policiesToCreate += @{
                Name     = $displayName
                Path     = $templateFile.FullName
                BodyJson = $jsonBody
                State    = 'disabled'
            }
        } catch {
            $errMessage = Get-GraphErrorMessage -ErrorRecord $_
            Write-HydrationLog -Message "  Failed: $displayName - $errMessage" -Level Warning
            $results += New-HydrationResult -Name $displayName -Type 'ConditionalAccessPolicy' -Action 'Failed' -Status $errMessage
        }
    }

    if (-not $PSCmdlet.ShouldProcess("$($policiesToCreate.Count) Conditional Access policies", "Create")) {
        if ($WhatIfPreference) {
            foreach ($policy in $policiesToCreate) {
                Write-HydrationLog -Message "  WouldCreate: $($policy.Name)" -Level Info
                $results += New-HydrationResult -Name $policy.Name -Type 'ConditionalAccessPolicy' -Action 'WouldCreate' -Status 'DryRun' -State 'disabled'
            }
        }
        return $results
    }

    if ($policiesToCreate.Count -gt 0) {
        $results += Invoke-GraphBatchOperation -Items $policiesToCreate -Operation 'POST' -BaseUrl '/identity/conditionalAccess/policies' -ResultType 'ConditionalAccessPolicy'
    }

    return $results
}
