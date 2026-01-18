function Test-IntunePrerequisites {
    <#
    .SYNOPSIS
        Validates Intune tenant prerequisites
    .DESCRIPTION
        Checks for Intune license availability, Azure AD Premium P2 license (for risk-based
        Conditional Access), and required Microsoft Graph permission scopes.

        Warnings are issued if Premium P2 is not found, as certain Conditional Access policies
        that use sign-in risk or user risk conditions require this license level.
    .EXAMPLE
        Test-IntunePrerequisites
    #>
    [CmdletBinding()]
    param()

    Write-Host "Validating Intune prerequisites..."

    $issues = @()

    # Required scopes from Connect-IntuneHydration
    $requiredScopes = @(
        "DeviceManagementConfiguration.ReadWrite.All",
        "DeviceManagementServiceConfig.ReadWrite.All",
        "DeviceManagementManagedDevices.ReadWrite.All",
        "DeviceManagementScripts.ReadWrite.All",
        "DeviceManagementApps.ReadWrite.All",
        "Group.ReadWrite.All",
        "Policy.Read.All",
        "Policy.ReadWrite.ConditionalAccess",
        "Application.Read.All",
        "Directory.ReadWrite.All",
        "LicenseAssignment.Read.All",
        "Organization.Read.All"
    )

    try {
        # Check organization info and licenses
        $org = Invoke-MgGraphRequest -Method GET -Uri "beta/organization" -ErrorAction Stop
        $orgDetails = $org.value[0]

        Write-Host "Connected to: $($orgDetails.displayName)"

        # Check for Intune service plan
        $subscribedSkus = Invoke-MgGraphRequest -Method GET -Uri "beta/subscribedSkus" -ErrorAction Stop

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
                    Write-Host "Found Intune license: $($plan.servicePlanName)"
                }
                if ($plan.servicePlanName -in $premiumP2ServicePlans -and $plan.provisioningStatus -eq 'Success') {
                    $hasPremiumP2 = $true
                    Write-Host "Found Premium P2 compatible license: $($plan.servicePlanName) in SKU $($sku.skuPartNumber)"
                }
            }
        }

        if (-not $hasIntune) {
            $issues += "No active Intune license found. Please ensure Intune is licensed for this tenant."
        }

        if (-not $hasPremiumP2) {
            Write-Warning "No Azure AD Premium P2 license found. Risk-based Conditional Access policies (sign-in risk, user risk) will be skipped."
            Write-Warning "Affected policies: 'Require multifactor authentication for risky sign-ins', 'Require password change for high-risk users', 'Block high risk agent identities', 'Block access to Office365 apps for users with insider risk'"
        }

        # Note about private preview features
        Write-Host "Note: Some Conditional Access templates use private preview features that require explicit tenant authorization."
        Write-Host "      Policies requiring preview features will be automatically skipped during import."

        # Check for required permission scopes
        $context = Get-MgContext
        if ($null -eq $context) {
            $issues += "Not connected to Microsoft Graph. Please run Connect-IntuneHydration first."
        } else {
            $isAppOnly = $context.AuthType -eq 'AppOnly' -or ($context.ClientId -and -not $context.Account)
            if ($isAppOnly) {
                # App-only auth uses app roles, so delegated scope validation does not apply
                Write-Host "App-only authentication detected - skipping delegated scope validation"
            } else {
                $currentScopes = $context.Scopes
                $missingScopes = @()

                foreach ($scope in $requiredScopes) {
                    if ($currentScopes -notcontains $scope) {
                        $missingScopes += $scope
                    }
                }

                if ($missingScopes.Count -gt 0) {
                    $issues += "Missing required permission scopes: $($missingScopes -join ', ')"
                    Write-Warning "Missing scopes detected. Please reconnect using Connect-IntuneHydration."
                } else {
                    Write-Host "All required permission scopes are present"
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
            throw "Prerequisite checks failed: $issueMessage"
        }

        Write-Host "All prerequisite checks passed"
        return $true
    } catch {
        if ($_.Exception.Message -match "Prerequisite checks failed") {
            throw
        }
        Write-Error "Failed to validate prerequisites: $_"
        throw
    }
}
