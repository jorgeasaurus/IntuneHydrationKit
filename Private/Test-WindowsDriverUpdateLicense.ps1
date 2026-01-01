function Test-WindowsDriverUpdateLicense {
    <#
    .SYNOPSIS
        Checks if the tenant has a license that supports Windows Driver Update profiles
    .DESCRIPTION
        Windows Driver Update profiles require one of the following licenses:
        - Windows 10/11 Enterprise E3 or E5
        - Windows 10/11 Education A3 or A5 (Microsoft 365 A3/A5)
        - Windows Virtual Desktop Access E3 or E5
        - Microsoft 365 Business Premium

        This function checks the tenant's subscribed SKUs for compatible service plans.
    .EXAMPLE
        Test-WindowsDriverUpdateLicense
        Returns $true if a compatible license is found, $false otherwise
    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    # Service plan names that enable Windows Driver Update profiles
    # Reference: https://learn.microsoft.com/en-us/mem/intune/protect/windows-driver-updates-overview
    $driverUpdateServicePlans = @(
        # Windows Enterprise E3/E5
        'WIN10_PRO_ENT_SUB',        # Windows 10/11 Enterprise E3
        'WIN10_ENT_A3_GOV',         # Windows 10/11 Enterprise E3 (Gov)
        'WIN10_ENT_A5_GOV',         # Windows 10/11 Enterprise E5 (Gov)
        'WINE5_GCC_COMPAT',         # Windows E5 GCC
        # Windows VDA
        'WIN10_VDA_E3',             # Windows Virtual Desktop Access E3
        'WIN10_VDA_E5',             # Windows Virtual Desktop Access E5
        'WINDOWS_STORE',            # Sometimes bundled with VDA
        # Microsoft 365 E3/E5 (includes Windows Enterprise)
        'SPE_E3',                   # Microsoft 365 E3
        'SPE_E5',                   # Microsoft 365 E5
        'SPE_E3_GOV',               # Microsoft 365 E3 (Gov)
        'SPE_E5_GOV',               # Microsoft 365 E5 (Gov)
        'SPE_E3_RPA1',              # Microsoft 365 E3 variant
        'M365_E3',                  # Microsoft 365 E3 (alternate)
        'M365_E5',                  # Microsoft 365 E5 (alternate)
        # Microsoft 365 Education A3/A5
        'M365EDU_A3_FACULTY',       # Microsoft 365 A3 for Faculty
        'M365EDU_A3_STUDENT',       # Microsoft 365 A3 for Students
        'M365EDU_A5_FACULTY',       # Microsoft 365 A5 for Faculty
        'M365EDU_A5_STUDENT',       # Microsoft 365 A5 for Students
        'SPE_E3_USGOV_GCCHIGH',     # Microsoft 365 E3 GCC High
        'SPE_E5_USGOV_GCCHIGH',     # Microsoft 365 E5 GCC High
        # Microsoft 365 Business Premium
        'SPB',                      # Microsoft 365 Business Premium
        'SMB_BUSINESS_PREMIUM',     # Microsoft 365 Business Premium (alternate)
        'O365_BUSINESS_PREMIUM',    # Microsoft 365 Business Premium (legacy)
        # Windows 365 Enterprise (includes Windows E3 entitlement)
        'CPC_E_2C_4GB_64GB',        # Windows 365 Enterprise variants
        'CPC_E_2C_8GB_128GB',
        'CPC_E_4C_16GB_128GB',
        'CPC_E_4C_16GB_256GB',
        'CPC_E_8C_32GB_128GB',
        'CPC_E_8C_32GB_256GB',
        'CPC_E_8C_32GB_512GB',
        # Intune Suite add-on (may include advanced features)
        'INTUNE_SUITE'
    )

    try {
        $subscribedSkus = Invoke-MgGraphRequest -Method GET -Uri "beta/subscribedSkus" -ErrorAction Stop

        foreach ($sku in $subscribedSkus.value) {
            # Skip disabled SKUs
            if ($sku.capabilityStatus -ne 'Enabled') {
                continue
            }

            foreach ($plan in $sku.servicePlans) {
                if ($plan.servicePlanName -in $driverUpdateServicePlans -and $plan.provisioningStatus -eq 'Success') {
                    Write-Verbose "Found Windows Driver Update compatible license: $($plan.servicePlanName) in SKU $($sku.skuPartNumber)"
                    return $true
                }
            }
        }

        Write-Verbose "No Windows Driver Update compatible license found in tenant"
        return $false
    }
    catch {
        Write-Warning "Failed to check Windows Driver Update license: $_"
        # Return $true to allow the attempt (will fail with 403 if truly not licensed)
        return $true
    }
}
