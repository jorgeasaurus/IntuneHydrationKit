@{
    # Module manifest for IntuneHydrationKit

    # Version number of this module
    ModuleVersion     = '0.8.1'

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
        # Main entry point
        'Invoke-IntuneHydration',
        # Core hydration functions
        'Connect-IntuneHydration',
        'Test-IntunePrerequisites',
        # Import functions
        'New-IntuneDynamicGroup',
        'New-IntuneStaticGroup',
        'Get-OpenIntuneBaseline',
        'Import-IntuneBaseline',
        'Import-CISBaseline',
        'Import-IntuneCompliancePolicy',
        'Import-IntuneAppProtectionPolicy',
        'Import-IntuneNotificationTemplate',
        'Import-IntuneEnrollmentProfile',
        'Import-IntuneDeviceFilter',
        'Import-IntuneConditionalAccessPolicy',
        'Import-IntuneMobileApp',
        'Import-IntuneWinGetApp',
        # Helper functions
        'Initialize-HydrationLogging',
        'Write-HydrationLog',
        'Import-HydrationSettings',
        # Result helpers (used by orchestrator)
        'New-HydrationResult',
        'Get-ResultSummary',
        'Get-GraphErrorMessage',
        # Safety helpers (used by orchestrator for deletion safety checks)
        'Test-HydrationKitObject',
        # Utility helpers
        'Get-ObfuscatedTenantId'
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

Install directly from the PowerShell Gallery:

```powershell
Install-Module -Name IntuneHydrationKit -Scope CurrentUser
```

To update to the latest version:

```powershell
Update-Module -Name IntuneHydrationKit
```

## v0.8.1

- **Authentication:** Interactive sign-in now uses a themed browser PKCE flow with fresh-token retry and no persistent refresh-token cache.
- **Mobile Apps:** Added bundled WinGet app templates and WinGet-backed Win32 app import support under the Mobile Apps workflow.
- **Pre-flight checks:** Device Filter runs now validate selected Intune workload access before imports and report concise authorization guidance.
- **Runtime permission checks:** Added selected-import access checks and clearer Global Administrator guidance for tenants where PIM-elevated roles may not be accepted by downstream Intune authorization.
- **Mobile Apps:** Fixed new mobile app names to append ` - [IHD]` after the app name instead of prefixing `[IHD]`.
- **Mobile Apps:** Fixed legacy Windows mobile app TemplateId matching for nested Store and M365 templates.
- **Sovereign clouds:** Centralized Graph environment metadata for consistent GCC High and DoD endpoint handling.

'@
        }
    }
}
