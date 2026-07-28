@{
    # Module manifest for IntuneHydrationKit

    # Version number of this module
    ModuleVersion     = '1.3.1'

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
        'Import-IntuneRemediation',
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

## v1.3.1

- **WinGet detection:** Prevented bootstrap log messages from corrupting the WinGet executable path.
- **OIB Settings Catalog:** Added a guarded assignment script that targets managed policies, preserves direct assignments, and fails closed on filtered or policy-set-owned targets.

'@
        }
    }
}
