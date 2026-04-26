function Test-IntunePrerequisites {
    <#
    .SYNOPSIS
        Validates Intune tenant prerequisites
    .DESCRIPTION
        Checks for Intune license availability, Azure AD Premium P2 license (for risk-based
        Conditional Access), and required Microsoft Graph permission scopes.

        Non-blocking notes are emitted when Premium P2 is not found, as certain Conditional
        Access policies that use sign-in risk or user risk conditions require this license level.
    .EXAMPLE
        Test-IntunePrerequisites
    #>
    [CmdletBinding()]
    param()

    Write-Information (Format-HydrationDisplayMessage -Message 'Validating Intune prerequisites...' -Style 'Section' -Emoji '🔎') -InformationAction Continue

    $issues = @()
    $notes = [System.Collections.Generic.List[object]]::new()
    $riskBasedPolicyNames = @()

    # Required scopes from Connect-IntuneHydration
    $requiredScopes = Get-HydrationGraphScopes

    try {
        # Check organization info and licenses
        $org = Invoke-MgGraphRequest -Method GET -Uri "beta/organization?`$select=id,displayName" -ErrorAction Stop
        $orgDetails = $org.value[0]

        Write-Information (Format-HydrationDisplayMessage -Message "Connected to: $($orgDetails.displayName)" -Style 'Info' -Emoji '🏢') -InformationAction Continue

        # Check for Intune service plan
        $subscribedSkus = Invoke-MgGraphRequest -Method GET -Uri "beta/subscribedSkus?`$select=id,skuPartNumber,capabilityStatus,servicePlans" -ErrorAction Stop
        $intuneServicePlans = @(
            'INTUNE_A',           # Intune Plan 1
            'INTUNE_EDU',         # Intune for Education
            'INTUNE_SMBIZ',       # Intune Small Business
            'AAD_PREMIUM',        # Azure AD Premium (includes some Intune features)
            'EMSPREMIUM'          # Enterprise Mobility + Security
        )

        # Premium P2 service plans (required for risk-based Conditional Access)
        $premiumP2ServicePlans = Get-PremiumP2ServicePlans

        $hasIntune = $false
        $hasPremiumP2 = $false

        foreach ($sku in $subscribedSkus.value) {
            # Skip disabled SKUs
            if ($sku.capabilityStatus -ne 'Enabled') {
                continue
            }

            foreach ($plan in $sku.servicePlans) {
                if ($plan.servicePlanName -in $intuneServicePlans -and $plan.provisioningStatus -eq 'Success') {
                    $hasIntune = $true
                    Write-Verbose "Found Intune license: $($plan.servicePlanName)"
                }
                if ($plan.servicePlanName -in $premiumP2ServicePlans -and $plan.provisioningStatus -eq 'Success') {
                    $hasPremiumP2 = $true
                    Write-Verbose "Found Premium P2 compatible license: $($plan.servicePlanName) in SKU $($sku.skuPartNumber)"
                }
            }
        }

        if (-not $hasIntune) {
            $issues += "No active Intune license found. Please ensure Intune is licensed for this tenant."
        }

        if (-not $hasPremiumP2) {
            $riskBasedPolicyNames = @(
                'Require multifactor authentication for risky sign-ins'
                'Require password change for high-risk users'
                'Block high risk agent identities'
                'Block access to Office365 apps for users with insider risk'
            )
            $notes.Add([PSCustomObject]@{
                    Message     = 'Azure AD Premium P2 not detected. Risk-based Conditional Access templates will be skipped:'
                    DetailLines = $riskBasedPolicyNames
                })
        }

        $notes.Add([PSCustomObject]@{
                Message     = 'Some Conditional Access templates use private preview features and will be skipped unless the tenant is explicitly authorized.'
                DetailLines = @()
            })

        # Check for required permission scopes
        $context = Get-MgContext
        if ($null -eq $context) {
            $issues += "Not connected to Microsoft Graph. Please run Connect-IntuneHydration first."
        } else {
            $isAppOnly = $context.AuthType -eq 'AppOnly' -or ($context.ClientId -and -not $context.Account)
            if ($isAppOnly) {
                # App-only auth uses app roles, so delegated scope validation does not apply
                $notes.Add([PSCustomObject]@{
                        Message     = 'App-only authentication detected; delegated scope validation was skipped.'
                        DetailLines = @()
                    })
            } else {
                $currentScopes = $context.Scopes
                $missingScopes = @($requiredScopes | Where-Object { $currentScopes -notcontains $_ })

                if ($missingScopes.Count -gt 0) {
                    $issues += "Missing required permission scopes: $($missingScopes -join ', ')"
                } else {
                    Write-Verbose 'All required permission scopes are present'
                }
            }
        }

        if ($notes.Count -gt 0) {
            Write-Information (Format-HydrationDisplayMessage -Message 'Notes:' -Style 'Section' -Emoji '📝') -InformationAction Continue
            foreach ($note in $notes) {
                Write-Information (Format-HydrationDisplayMessage -Message $note.Message -Style 'Info' -Emoji '•' -Indent 2) -InformationAction Continue

                foreach ($policyName in $note.DetailLines) {
                    Write-Information (Format-HydrationDisplayMessage -Message "'$policyName'" -Style 'Muted' -Emoji '↳' -Indent 4) -InformationAction Continue
                }
            }
        }

        # Report results
        if ($issues.Count -gt 0) {
            foreach ($issue in $issues) {
                Write-Warning $issue
            }

            # Surface specific issues in the exception message so callers/tests can pattern match
            $issueMessage = $issues -join ' | '
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("Prerequisite checks failed: $issueMessage"),
                'PrerequisiteCheckFailed',
                [System.Management.Automation.ErrorCategory]::NotEnabled,
                $null
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        Write-Information (Format-HydrationDisplayMessage -Message 'Pre-flight checks passed' -Style 'Success' -Emoji '✅') -InformationAction Continue
        return $true
    } catch {
        if ($_.Exception.Message -match "Prerequisite checks failed") {
            throw
        }
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("Failed to validate prerequisites: $($_.Exception.Message)", $_.Exception),
            'PrerequisiteValidationFailed',
            [System.Management.Automation.ErrorCategory]::NotSpecified,
            $null
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }
}
