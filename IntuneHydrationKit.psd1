@{
    # Module manifest for IntuneHydrationKit

    # Version number of this module
    ModuleVersion = '0.1.0'

    # ID used to uniquely identify this module
    GUID = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'

    # Author of this module
    Author = 'Jorge Balderas'

    # Company or vendor of this module
    CompanyName = 'Community'

    # Copyright statement for this module
    Copyright = '(c) 2024 Jorge Balderas. All rights reserved.'

    # Description of the functionality provided by this module
    Description = 'Hydrates Microsoft Intune tenants with best-practice baseline configurations including policies, compliance packs, enrollment profiles, dynamic groups, security baselines, and conditional access starter packs.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.0'

    # Root module file
    RootModule = 'IntuneHydrationKit.psm1'

    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules = @(
        @{ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.0.0'}
        @{ModuleName = 'Microsoft.Graph.Groups'; ModuleVersion = '2.0.0'}
        @{ModuleName = 'Microsoft.Graph.Identity.SignIns'; ModuleVersion = '2.0.0'}
        @{ModuleName = 'Microsoft.Graph.DeviceManagement'; ModuleVersion = '2.0.0'}
    )

    # Functions to export from this module
    FunctionsToExport = @(
        # Core hydration functions
        'Invoke-IntuneHydration',
        'Connect-IntuneHydration',
        'Test-IntunePrerequisites',
        'Get-HydrationSummary',
        # Import functions
        'New-IntuneDynamicGroup',
        'Get-OpenIntuneBaseline',
        'Import-IntuneBaseline',
        'Import-IntuneCompliancePolicy',
        'Import-IntuneAppProtectionPolicy',
        'Import-IntuneNotificationTemplate',
        'Import-IntuneEnrollmentProfile',
        'Import-IntuneDeviceFilter',
        'Import-IntuneConditionalAccessPolicy',
        # Helper functions
        'Initialize-HydrationLogging',
        'Write-HydrationLog',
        'Invoke-GraphRequestWithRetry',
        'Get-TemplateFiles',
        'Import-TemplateFile',
        'Resolve-TemplateTokens',
        'Get-UpsertDecision',
        'Import-HydrationSettings',
        # Result helpers (used by orchestrator)
        'New-HydrationResult',
        'Get-ResultSummary',
        'Get-GraphErrorMessage'
    )

    # Cmdlets to export from this module
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module
    AliasesToExport = @()

    # Private data to pass to the module specified in RootModule
    PrivateData = @{
        PSData = @{
            # Tags applied to this module for module discovery
            Tags = @('Intune', 'Microsoft365', 'Graph', 'Baseline', 'Compliance', 'Security', 'Autopilot', 'MDM')

            # License URI for this module
            LicenseUri = 'https://github.com/yourusername/Intune-Hydration-Kit/blob/main/LICENSE'

            # Project URI for this module
            ProjectUri = 'https://github.com/yourusername/Intune-Hydration-Kit'

            # Release notes for this module
            ReleaseNotes = 'Initial release - MVP functionality for Intune tenant hydration.'

            # Prerelease string of this module
            Prerelease = 'alpha'
        }
    }
}
