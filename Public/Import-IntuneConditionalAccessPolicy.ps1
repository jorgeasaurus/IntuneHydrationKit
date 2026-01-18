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
        [string]$Prefix = "",

        [Parameter()]
        [switch]$RemoveExisting
    )

    # Use default template path if not specified
    if (-not $TemplatePath) {
        $TemplatePath = Join-Path -Path $script:TemplatesPath -ChildPath "ConditionalAccess"
    }

    if (-not (Test-Path -Path $TemplatePath)) {
        throw "Conditional Access template directory not found: $TemplatePath"
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
        $subscribedSkus = Invoke-MgGraphRequest -Method GET -Uri "beta/subscribedSkus" -ErrorAction Stop
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

    # Get template names (file names without extension become policy names with prefix)
    $templateNames = @()
    foreach ($templateFile in $templateFiles) {
        $policyName = "$Prefix$([System.IO.Path]::GetFileNameWithoutExtension($templateFile.Name))"
        $templateNames += $policyName
    }

    # Prefetch existing CA policies
    $existingPolicies = @{}
    try {
        $listUri = "beta/identity/conditionalAccess/policies?`$select=id,displayName,state"
        do {
            $existing = Invoke-MgGraphRequest -Method GET -Uri $listUri -ErrorAction Stop
            foreach ($policy in $existing.value) {
                if (-not $existingPolicies.ContainsKey($policy.displayName)) {
                    $existingPolicies[$policy.displayName] = @{
                        Id    = $policy.id
                        State = $policy.state
                    }
                }
            }
            $listUri = $existing.'@odata.nextLink'
        } while ($listUri)
    } catch {
        Write-Warning "Could not retrieve existing CA policies: $_"
    }

    # Remove existing CA policies if requested
    # SAFETY: Conditional Access policies do not have a description field, so we identify
    # policies by matching template names. Additionally, we ONLY delete policies that are
    # in disabled state to prevent accidental deletion of enabled policies.
    if ($RemoveExisting) {
        $policiesToDelete = @()
        foreach ($policyName in $existingPolicies.Keys) {
            if ($policyName -notin $templateNames) {
                continue
            }

            $policyInfo = $existingPolicies[$policyName]

            if ($policyInfo.State -ne 'disabled') {
                Write-HydrationLog -Message "  Skipped: $policyName - policy is not disabled (state: $($policyInfo.State))" -Level Warning
                $results += New-HydrationResult -Name $policyName -Type 'ConditionalAccessPolicy' -Action 'Skipped' -Status "Not deleted: policy is $($policyInfo.State) (must be disabled)"
                continue
            }

            $policiesToDelete += @{
                Name = $policyName
                Id   = $policyInfo.Id
            }
        }

        if ($policiesToDelete.Count -eq 0) {
            Write-Verbose "No Conditional Access policies found to delete"
            return $results
        }

        if ($WhatIfPreference) {
            foreach ($policy in $policiesToDelete) {
                Write-HydrationLog -Message "  WouldDelete: $($policy.Name)" -Level Info
                $results += New-HydrationResult -Name $policy.Name -Type 'ConditionalAccessPolicy' -Action 'WouldDelete' -Status 'DryRun'
            }
            return $results
        }

        return Invoke-GraphBatchOperation -Items $policiesToDelete -Operation 'DELETE' -BaseUrl '/identity/conditionalAccess/policies' -ResultType 'ConditionalAccessPolicy'
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

    if ($WhatIfPreference) {
        foreach ($policy in $policiesToCreate) {
            Write-HydrationLog -Message "  WouldCreate: $($policy.Name)" -Level Info
            $results += New-HydrationResult -Name $policy.Name -Type 'ConditionalAccessPolicy' -Action 'WouldCreate' -Status 'DryRun' -State 'disabled'
        }
        return $results
    }

    if ($policiesToCreate.Count -gt 0) {
        $results += Invoke-GraphBatchOperation -Items $policiesToCreate -Operation 'POST' -BaseUrl '/identity/conditionalAccess/policies' -ResultType 'ConditionalAccessPolicy'
    }

    return $results
}