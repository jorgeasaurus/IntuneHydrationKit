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

    $results = @()

    # Remove existing CA policies if requested
    # SAFETY: Conditional Access policies do not have a description field, so we identify
    # policies by matching template names. Additionally, we ONLY delete policies that are
    # in disabled state to prevent accidental deletion of enabled policies.
    if ($RemoveExisting) {
        # Get template names (file names without extension become policy names with prefix)
        $templateNames = @()
        foreach ($templateFile in $templateFiles) {
            $policyName = "$Prefix$([System.IO.Path]::GetFileNameWithoutExtension($templateFile.Name))"
            $templateNames += $policyName
        }

        try {
            $listUri = "beta/identity/conditionalAccess/policies"
            do {
                $existingPolicies = Invoke-MgGraphRequest -Method GET -Uri $listUri -ErrorAction Stop
                foreach ($policy in $existingPolicies.value) {
                    # Safety check 1: Only delete if it matches a template name
                    if ($policy.displayName -notin $templateNames) {
                        continue
                    }

                    # Safety check 2: Only delete if policy is disabled
                    if ($policy.state -ne 'disabled') {
                        Write-HydrationLog -Message "  Skipped: $($policy.displayName) - policy is not disabled (state: $($policy.state))" -Level Warning
                        $results += New-HydrationResult -Name $policy.displayName -Type 'ConditionalAccessPolicy' -Action 'Skipped' -Status "Not deleted: policy is $($policy.state) (must be disabled)"
                        continue
                    }

                    if ($PSCmdlet.ShouldProcess($policy.displayName, "Delete Conditional Access policy")) {
                        try {
                            Invoke-MgGraphRequest -Method DELETE -Uri "beta/identity/conditionalAccess/policies/$($policy.id)" -ErrorAction Stop
                            Write-HydrationLog -Message "  Deleted: $($policy.displayName)" -Level Info
                            $results += New-HydrationResult -Name $policy.displayName -Type 'ConditionalAccessPolicy' -Action 'Deleted' -Status 'Success'
                        }
                        catch {
                            $errMessage = Get-GraphErrorMessage -ErrorRecord $_
                            Write-HydrationLog -Message "  Failed: $($policy.displayName) - $errMessage" -Level Warning
                            $results += New-HydrationResult -Name $policy.displayName -Type 'ConditionalAccessPolicy' -Action 'Failed' -Status "Delete failed: $errMessage"
                        }
                    }
                    else {
                        Write-HydrationLog -Message "  WouldDelete: $($policy.displayName)" -Level Info
                        $results += New-HydrationResult -Name $policy.displayName -Type 'ConditionalAccessPolicy' -Action 'WouldDelete' -Status 'DryRun'
                    }
                }
                $listUri = $existingPolicies.'@odata.nextLink'
            } while ($listUri)
        }
        catch {
            Write-Warning "Failed to list CA policies: $_"
        }

        return $results
    }

    foreach ($templateFile in $templateFiles) {
        $policyName = [System.IO.Path]::GetFileNameWithoutExtension($templateFile.Name)
        $displayName = "$Prefix$policyName"

        try {
            # Load template
            $templateContent = Get-Content -Path $templateFile.FullName -Raw -Encoding utf8
            $policy = $templateContent | ConvertFrom-Json

            # Check if policy already exists (escape single quotes for OData filter)
            $safeDisplayName = $displayName -replace "'", "''"
            $existingPolicies = Invoke-MgGraphRequest -Method GET -Uri "beta/identity/conditionalAccess/policies?`$filter=displayName eq '$safeDisplayName'" -ErrorAction Stop

            if ($existingPolicies.value.Count -gt 0) {
                Write-HydrationLog -Message "  Skipped: $displayName" -Level Info
                $results += New-HydrationResult -Name $displayName -Id $existingPolicies.value[0].id -Action 'Skipped' -Status 'Already exists' -State $existingPolicies.value[0].state
                continue
            }

            if ($PSCmdlet.ShouldProcess($displayName, "Create Conditional Access policy (disabled)")) {
                # Build the policy body - force state to disabled
                $policyBody = @{
                    displayName = $displayName
                    state = "disabled"  # Always disabled for safety
                    conditions = $policy.conditions
                    grantControls = $policy.grantControls
                }

                # Add session controls if present
                if ($policy.sessionControls) {
                    $policyBody.sessionControls = $policy.sessionControls
                }

                # Remove any odata context properties that shouldn't be in create request
                $jsonBody = $policyBody | ConvertTo-Json -Depth 20
                $jsonBody = $jsonBody -replace '"@odata\.[^"]*":\s*"[^"]*",?\s*', ''
                $jsonBody = $jsonBody -replace '"@odata\.[^"]*":\s*null,?\s*', ''

                # Create the policy
                $newPolicy = Invoke-MgGraphRequest -Method POST -Uri "beta/identity/conditionalAccess/policies" -Body $jsonBody -ContentType "application/json" -ErrorAction Stop

                Write-HydrationLog -Message "  Created: $displayName" -Level Info

                $results += New-HydrationResult -Name $displayName -Id $newPolicy.id -Action 'Created' -Status 'Success' -State 'disabled'
            }
            else {
                Write-HydrationLog -Message "  WouldCreate: $displayName" -Level Info
                $results += New-HydrationResult -Name $displayName -Action 'WouldCreate' -Status 'DryRun' -State 'disabled'
            }
        }
        catch {
            $errMessage = Get-GraphErrorMessage -ErrorRecord $_
            Write-HydrationLog -Message "  Failed: $displayName - $errMessage" -Level Warning
            $results += New-HydrationResult -Name $displayName -Action 'Failed' -Status $errMessage
        }
    }

    return $results
}