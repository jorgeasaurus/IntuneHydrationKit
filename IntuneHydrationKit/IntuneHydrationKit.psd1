#
# Module manifest for module 'IntuneHydrationKit'
#

@{

# Script module or binary module file associated with this manifest.
RootModule = 'IntuneHydrationKit.psm1'

# Version number of this module.
ModuleVersion = '1.0.0'

# Supported PSEditions
CompatiblePSEditions = @('Desktop', 'Core')

# ID used to uniquely identify this module
GUID = 'b722886b-c95d-4adf-ad86-7711eaa1e1f8'

# Author of this module
Author = 'Intune Hydration Kit'

# Company or vendor of this module
CompanyName = 'Community'

# Copyright statement for this module
Copyright = '(c) 2025. All rights reserved.'

# Description of the functionality provided by this module
Description = 'PowerShell module for hydrating Microsoft Intune tenants with best-practice policies, compliance baselines, security settings, enrollment profiles, dynamic groups, and Conditional Access policies. Integrates OpenIntuneBaseline and IntuneManagement repositories.'

# Minimum version of the PowerShell engine required by this module
PowerShellVersion = '5.1'

# Modules that must be imported into the global environment prior to importing this module
# RequiredModules = @()
# Note: The module will check for and install these if missing:
# - Microsoft.Graph.Authentication
# - Microsoft.Graph.DeviceManagement
# - Microsoft.Graph.Groups
# - Microsoft.Graph.Identity.SignIns

# Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
FunctionsToExport = @(
    'Invoke-IntuneHydration',
    'Import-IntuneOpenBaseline',
    'Import-IntuneComplianceBaselines',
    'Import-IntuneSecurityBaselines',
    'New-IntuneEnrollmentProfiles',
    'New-IntuneDynamicGroups',
    'Import-IntuneConditionalAccessPolicies'
)

# Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
CmdletsToExport = @()

# Variables to export from this module
VariablesToExport = @()

# Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
AliasesToExport = @()

# Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
PrivateData = @{

    PSData = @{

        # Tags applied to this module. These help with module discovery in online galleries.
        Tags = @('Intune', 'Azure', 'MicrosoftGraph', 'DeviceManagement', 'Compliance', 'Security', 'Autopilot', 'ConditionalAccess')

        # A URL to the license for this module.
        LicenseUri = 'https://github.com/jorgeasaurus/Intune-Hydration-Kit/blob/main/LICENSE'

        # A URL to the main website for this project.
        ProjectUri = 'https://github.com/jorgeasaurus/Intune-Hydration-Kit'

        # ReleaseNotes of this module
        ReleaseNotes = '
v1.0.0 - Initial Release
- Intune tenant hydration framework
- OpenIntuneBaseline policy import templates
- Compliance baseline pack (Windows, iOS, Android, macOS)
- Microsoft Security Baselines templates
- Autopilot and ESP enrollment profiles
- 14 dynamic groups for device management
- 10 Conditional Access policy templates (disabled by default)
- Integration with OpenIntuneBaseline and IntuneManagement repositories
'

    } # End of PSData hashtable

} # End of PrivateData hashtable

# HelpInfo URI of this module
HelpInfoURI = 'https://github.com/jorgeasaurus/Intune-Hydration-Kit'

}
