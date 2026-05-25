function Get-PremiumP2ServicePlans {
    <#
    .SYNOPSIS
        Returns the list of service plan names that include Azure AD Premium P2 features
    .DESCRIPTION
        This function provides a centralized definition of service plans that include
        Azure AD Premium P2 capabilities, which are required for risk-based Conditional
        Access policies (signInRiskLevels, userRiskLevels, insiderRiskLevels, etc.).

        Used by Test-IntunePrerequisites and Import-IntuneConditionalAccessPolicy to
        maintain a single source of truth for P2 license detection.
    .EXAMPLE
        $p2Plans = Get-PremiumP2ServicePlans
        if ($plan.servicePlanName -in $p2Plans) { ... }
    .OUTPUTS
        System.String[]
    .NOTES
        Reference: https://learn.microsoft.com/en-us/azure/active-directory/conditional-access/concept-conditional-access-conditions
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    return @(
        # Azure AD Premium P2 standalone
        'AAD_PREMIUM_P2',           # Azure AD Premium P2

        # Microsoft 365 E5 suites (include Azure AD Premium P2)
        'SPE_E5',                   # Microsoft 365 E5
        'SPE_E5_GOV',               # Microsoft 365 E5 (Gov)
        'M365_E5',                  # Microsoft 365 E5 (alternate)
        'SPE_E5_USGOV_GCCHIGH',     # Microsoft 365 E5 GCC High
        'INFORMATION_PROTECTION_COMPLIANCE', # Microsoft 365 E5 Compliance
        'M365_E5_SUITE_COMPONENTS', # Microsoft 365 E5 Suite

        # Microsoft 365 Education A5 (includes Azure AD Premium P2)
        'M365EDU_A5_FACULTY',       # Microsoft 365 A5 for Faculty
        'M365EDU_A5_STUDENT',       # Microsoft 365 A5 for Students

        # Enterprise Mobility + Security E5
        'EMSPREMIUM',               # Enterprise Mobility + Security E5
        'EMS',                      # EMS E5 (alternate)

        # Identity & Threat Protection (standalone add-on)
        'IDENTITY_THREAT_PROTECTION', # Microsoft 365 E5 Security

        # Microsoft Defender for Cloud Apps (formerly MCAS) - includes some Identity Protection features
        'ADALLOM_S_STANDALONE',     # Microsoft Defender for Cloud Apps

        # Azure Advanced Threat Protection (now part of Defender for Identity)
        'ATA'                       # Azure ATP
    )
}
