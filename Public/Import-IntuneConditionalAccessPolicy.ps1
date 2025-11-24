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
        [switch]$Force,

        [Parameter()]
        [switch]$RemoveExisting,

        [Parameter()]
        [switch]$TestMode
    )

    # Use default template path if not specified
    if (-not $TemplatePath) {
        $TemplatePath = Join-Path -Path $script:TemplatesPath -ChildPath "ConditionalAccess"
    }

    if (-not (Test-Path -Path $TemplatePath)) {
        throw "Conditional Access template directory not found: $TemplatePath"
    }

    # Get all CA policy templates
    $templateFiles = Get-ChildItem -Path $TemplatePath -Filter "*.json" -File

    if ($templateFiles.Count -eq 0) {
        Write-Warning "No Conditional Access templates found in: $TemplatePath"
        return @()
    }

    # Test mode - only process first template
    if ($TestMode -and $templateFiles.Count -gt 0) {
        $templateFiles = $templateFiles | Select-Object -First 1
        Write-Host "Test mode: Processing only first template: $($templateFiles.Name)" -InformationAction Continue
    }

    Write-Host "Found $($templateFiles.Count) Conditional Access policy templates" -InformationAction Continue

    $results = @()

    # Remove existing CA policies if requested - ONLY policies that match our templates
    if ($RemoveExisting) {
        # Get template names (file names without extension become policy names with prefix)
        $templateNames = @()
        foreach ($templateFile in $templateFiles) {
            $policyName = "$Prefix$([System.IO.Path]::GetFileNameWithoutExtension($templateFile.Name))"
            $templateNames += $policyName
        }

        Write-Host "Removing managed Conditional Access policies..." -InformationAction Continue

        try {
            $existingPolicies = Invoke-MgGraphRequest -Method GET -Uri "beta/identity/conditionalAccess/policies" -ErrorAction Stop
            foreach ($policy in $existingPolicies.value) {
                # Only delete if it matches a template name
                if ($policy.displayName -notin $templateNames) {
                    continue
                }

                if ($PSCmdlet.ShouldProcess($policy.displayName, "Delete Conditional Access policy")) {
                    try {
                        Invoke-MgGraphRequest -Method DELETE -Uri "beta/identity/conditionalAccess/policies/$($policy.id)" -ErrorAction Stop
                        Write-Host "Deleted CA policy: $($policy.displayName)" -InformationAction Continue
                        $results += New-HydrationResult -Name $policy.displayName -Type 'ConditionalAccessPolicy' -Action 'Deleted' -Status 'Success'
                    }
                    catch {
                        $errMessage = Get-GraphErrorMessage -ErrorRecord $_
                        Write-Warning "Failed to delete CA policy '$($policy.displayName)': $errMessage"
                        $results += New-HydrationResult -Name $policy.displayName -Type 'ConditionalAccessPolicy' -Action 'Failed' -Status "Delete failed: $errMessage"
                    }
                }
                else {
                    $results += New-HydrationResult -Name $policy.displayName -Type 'ConditionalAccessPolicy' -Action 'WouldDelete' -Status 'DryRun'
                }
            }
        }
        catch {
            Write-Warning "Failed to list CA policies: $_"
        }

        # RemoveExisting mode - only delete, don't create
        $summary = Get-ResultSummary -Results $results
        Write-Host "Conditional Access removal complete: $($summary.Deleted) deleted, $($summary.Failed) failed" -InformationAction Continue
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
                Write-Host "  Skipped: $displayName (already exists)" -InformationAction Continue
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

                Write-Host "  Created: $displayName" -InformationAction Continue

                $results += New-HydrationResult -Name $displayName -Id $newPolicy.id -Action 'Created' -Status 'Success' -State 'disabled'
            }
            else {
                $results += New-HydrationResult -Name $displayName -Action 'WouldCreate' -Status 'DryRun' -State 'disabled'
            }
        }
        catch {
            Write-Error "Failed to create policy '$displayName': $_"
            $results += New-HydrationResult -Name $displayName -Action 'Failed' -Status $_.Exception.Message
        }
    }

    # Summary
    $summary = Get-ResultSummary -Results $results

    Write-Host "Conditional Access import complete: $($summary.Created) created, $($summary.Skipped) skipped, $($summary.Failed) failed" -InformationAction Continue
    Write-Host "IMPORTANT: All policies were created in DISABLED state. Review and enable as needed." -InformationAction Continue

    return $results
}