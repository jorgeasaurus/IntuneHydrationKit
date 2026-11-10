@{
    # Module manifest for IntuneHydrationKit

    # Version number of this module
    ModuleVersion     = '1.4.1'

    # ID used to uniquely identify this module
    GUID              = 'f755f41b-d5fc-48db-8b11-62b7ed71b1cd'

    # Author of this module
    Author            = 'Jorgeasaurus'

    # Company or vendor of this module
    CompanyName       = 'Jorgeasaurus'

    # Copyright statement for this module
    Copyright         = '(c) 2026 Jorgeasaurus. All rights reserved.'

    # Description of the functionality provided by this module
    Description       = 'Hydrates Microsoft Intune tenants with best-practice baseline configurations including policies, compliance packs, enrollment profiles, dynamic groups, security baselines, and conditional access starter packs.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.0'

    # Root module file
    RootModule        = 'IntuneHydrationKit.psm1'

    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules   = @(
        @{ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.0.0' }
    )

    # Functions to export from this module
    FunctionsToExport = @(
        'Connect-IntuneHydration',
        'Get-GraphErrorMessage',
        'Get-ObfuscatedTenantId',
        'Get-OpenIntuneBaseline',
        'Get-ResultSummary',
        'Import-CISBaseline',
        'Import-HydrationSettings',
        'Import-IntuneAppProtectionPolicy',
        'Import-IntuneBaseline',
        'Import-IntuneCompliancePolicy',
        'Import-IntuneConditionalAccessPolicy',
        'Import-IntuneDeviceFilter',
        'Import-IntuneEnrollmentProfile',
        'Import-IntuneMobileApp',
        'Import-IntuneNotificationTemplate',
        'Import-IntuneWinGetApp',
        'Initialize-HydrationLogging',
        'Invoke-IntuneHydration',
        'New-HydrationResult',
        'New-IntuneDynamicGroup',
        'New-IntuneStaticGroup',
        'Test-HydrationKitObject',
        'Test-IntunePrerequisites',
        'Write-HydrationLog'
    )

    # Cmdlets to export from this module
    CmdletsToExport   = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module
    AliasesToExport   = @()

    # Private data to pass to the module specified in RootModule
    PrivateData       = @{
        PSData = @{
            # Tags applied to this module for module discovery
            Tags         = @('Intune', 'Microsoft365', 'Graph', 'Baseline', 'Compliance', 'Security', 'Autopilot', 'MDM', 'Endpoint', 'MEM', 'Azure', 'EntraID', 'ConditionalAccess', 'DeviceManagement', 'PSEdition_Core')

            # License URI for this module
            LicenseUri   = 'https://github.com/jorgeasaurus/Intune-Hydration-Kit/blob/main/LICENSE'

            # Project URI for this module
            ProjectUri   = 'https://intunehydrationkit.com'

            # Icon URI for the module (used in PSGallery)
            IconUri = 'https://raw.githubusercontent.com/jorgeasaurus/Intune-Hydration-Kit/main/media/IHTLogoClearLight.png'

            # Release notes for this module
            ReleaseNotes = @'

## v1.4.1

- Refresh bundled OpenIntuneBaseline to Windows v4.0.1 (Administrator Protection v4.0.1, Config Refresh update) and BYOD v2.0 (Android/iOS App Protection - U - BYOD L2+ - v2.0, replacing the previous BYOD app protection templates).
- Carry the upstream warning on the Windows script file association policy: deploying it breaks Intune PowerShell scripts that run in the user context.
- Bundle the OpenIntuneBaseline releases.json catalog.
- Keep Pester tests compatible with Pester 6.

'@
        }
    }
}
