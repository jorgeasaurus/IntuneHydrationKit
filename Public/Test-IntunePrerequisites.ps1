function Test-IntunePrerequisites {
    <#
    .SYNOPSIS
        Validates Intune tenant prerequisites
    .DESCRIPTION
        Checks for Intune license availability and MDM authority configuration
    .EXAMPLE
        Test-IntunePrerequisites
    #>
    [CmdletBinding()]
    param()

    Write-Information "Validating Intune prerequisites..." -InformationAction Continue

    $issues = @()

    try {
        # Check organization info and licenses
        $org = Invoke-MgGraphRequest -Method GET -Uri "v1.0/organization" -ErrorAction Stop
        $orgDetails = $org.value[0]

        Write-Information "Connected to: $($orgDetails.displayName)" -InformationAction Continue

        # Check for Intune service plan
        $subscribedSkus = Invoke-MgGraphRequest -Method GET -Uri "v1.0/subscribedSkus" -ErrorAction Stop

        $intuneServicePlans = @(
            'INTUNE_A',           # Intune Plan 1
            'INTUNE_EDU',         # Intune for Education
            'INTUNE_SMBIZ',       # Intune Small Business
            'AAD_PREMIUM',        # Azure AD Premium (includes some Intune features)
            'EMSPREMIUM'          # Enterprise Mobility + Security
        )

        $hasIntune = $false
        foreach ($sku in $subscribedSkus.value) {
            foreach ($plan in $sku.servicePlans) {
                if ($plan.servicePlanName -in $intuneServicePlans -and $plan.provisioningStatus -eq 'Success') {
                    $hasIntune = $true
                    Write-Information "Found Intune license: $($plan.servicePlanName)" -InformationAction Continue
                    break
                }
            }
            if ($hasIntune) { break }
        }

        if (-not $hasIntune) {
            $issues += "No active Intune license found. Please ensure Intune is licensed for this tenant."
        }

        # Check MDM Authority
        $mdmPolicies = Invoke-MgGraphRequest -Method GET -Uri "beta/policies/mobileDeviceManagementPolicies?`$select=displayName,id,isValid" -ErrorAction Stop

        $intuneMdm = $mdmPolicies.value | Where-Object { $_.displayName -eq 'Microsoft Intune' -or $_.displayName -eq 'Microsoft Intune Enrollment' }

        if (-not $intuneMdm) {
            $issues += "MDM Authority is not configured. Please set up Microsoft Intune as the MDM authority."
        }
        elseif ($intuneMdm | Where-Object { $_.isValid -eq $false }) {
            $issues += "Microsoft Intune MDM policy exists but is not valid. Please verify MDM authority configuration."
        }
        else {
            Write-Information "MDM Authority: Microsoft Intune (OK)" -InformationAction Continue
        }

        # Report results
        if ($issues.Count -gt 0) {
            foreach ($issue in $issues) {
                Write-Warning $issue
            }
            throw "Prerequisite checks failed. Please resolve the issues above before continuing."
        }

        Write-Information "All prerequisite checks passed" -InformationAction Continue
        return $true
    }
    catch {
        if ($_.Exception.Message -match "Prerequisite checks failed") {
            throw
        }
        Write-Error "Failed to validate prerequisites: $_"
        throw
    }
}