# Intune Hydration Kit

> **⚠️ IMPORTANT**: This is now a **PowerShell module** following PSStucco best practices. The original standalone script (`Invoke-IntuneHydration.ps1`) remains for backwards compatibility, but the recommended approach is to use the module.

Quick way to import starter configurations into Microsoft Intune. This PowerShell module automates the process of "hydrating" a new or existing Intune tenant with best-practice configurations, policies, profiles, and groups.

## Quick Start

### Using the Module (Recommended)

```powershell
# Import the module
Import-Module .\IntuneHydrationKit\IntuneHydrationKit.psd1

# Run the hydration
Invoke-IntuneHydration

# Or with specific options
Invoke-IntuneHydration -SkipEnrollment -SkipGroups
```

### Using the Standalone Script (Legacy)

```powershell
.\Invoke-IntuneHydration.ps1
```

## Overview

**The Intune Hydration Kit is now available as a PowerShell module!**

This module provides a comprehensive framework for hydrating Microsoft Intune tenants with best-practice configurations:

- **OpenIntuneBaseline Policies**: All configuration policies from the OpenIntuneBaseline repository
- **Compliance Baselines**: Multi-platform compliance policies (Windows, iOS, Android, macOS)
- **Microsoft Security Baselines**: Windows, Edge, Windows 365, and Defender for Endpoint baselines
- **Enrollment Profiles**: Autopilot and Enrollment Status Page (ESP) profiles
- **Dynamic Groups**: Automated grouping by OS, manufacturer, model, Autopilot status, and compliance state (14 groups)
- **Conditional Access Policies**: 10-policy starter pack (all disabled by default for safe deployment)

> **Framework Approach**: This module provides comprehensive templates and structure with Microsoft Graph API calls documented as comments. Users can uncomment and customize these API calls based on their specific needs, or use as a reference for building their own automation.

## Module Structure

The kit is now organized as a proper PowerShell module:

```
Intune-Hydration-Kit/
├── IntuneHydrationKit/          # PowerShell Module
│   ├── IntuneHydrationKit.psd1  # Module manifest
│   ├── IntuneHydrationKit.psm1  # Root module file
│   ├── README.md                # Module documentation
│   ├── Private/                 # Private helper functions
│   │   ├── Connect-IntuneGraph.ps1
│   │   ├── Get-IntuneGitHubRepository.ps1
│   │   ├── Test-IntunePrerequisites.ps1
│   │   └── Write-IntuneLog.ps1
│   └── Public/                  # Public exported functions
│       ├── Import-IntuneComplianceBaselines.ps1
│       ├── Import-IntuneConditionalAccessPolicies.ps1
│       ├── Import-IntuneOpenBaseline.ps1
│       ├── Import-IntuneSecurityBaselines.ps1
│       ├── Invoke-IntuneHydration.ps1
│       ├── New-IntuneDynamicGroups.ps1
│       └── New-IntuneEnrollmentProfiles.ps1
├── Invoke-IntuneHydration.ps1   # Legacy standalone script
├── Config.json                  # Configuration file
├── README.md                    # This file
├── QUICKSTART.md                # Quick start guide
├── EXAMPLES.md                  # Usage examples
└── IMPLEMENTATION.md            # Technical details
```

## Prerequisites

### Software Requirements
- **PowerShell 5.1** or higher
- **Git** (for cloning baseline repositories)
- **Internet connectivity** to access GitHub and Microsoft Graph

### Required PowerShell Modules
The script will automatically install these if missing:
- `Microsoft.Graph.Authentication`
- `Microsoft.Graph.DeviceManagement`
- `Microsoft.Graph.Groups`
- `Microsoft.Graph.Identity.SignIns`

### Permissions Required
You need an account with the following Microsoft Graph permissions:
- `DeviceManagementConfiguration.ReadWrite.All`
- `DeviceManagementManagedDevices.ReadWrite.All`
- `DeviceManagementServiceConfig.ReadWrite.All`
- `Group.ReadWrite.All`
- `Policy.ReadWrite.ConditionalAccess`
- `Directory.Read.All`

## Installation

### Using the Module (Recommended)

```powershell
# Clone the repository
git clone https://github.com/jorgeasaurus/Intune-Hydration-Kit.git
cd Intune-Hydration-Kit

# Import the module
Import-Module .\IntuneHydrationKit\IntuneHydrationKit.psd1

# Or install to PowerShell modules directory
$modulePath = "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\IntuneHydrationKit"
Copy-Item -Path .\IntuneHydrationKit -Destination $modulePath -Recurse -Force
Import-Module IntuneHydrationKit
```

### Using the Standalone Script (Legacy)

```powershell
# Clone the repository
git clone https://github.com/jorgeasaurus/Intune-Hydration-Kit.git
cd Intune-Hydration-Kit

# No installation needed - just run the script
.\Invoke-IntuneHydration.ps1
```

## Usage

### Module Usage (Recommended)

```powershell
# Import the module
Import-Module IntuneHydrationKit

# Run full hydration
Invoke-IntuneHydration

# Run with selective components
Invoke-IntuneHydration -SkipPolicies -SkipConditionalAccess

# Use individual functions
Import-IntuneComplianceBaselines
New-IntuneDynamicGroups
Import-IntuneConditionalAccessPolicies

# Custom logging and options
Invoke-IntuneHydration -LogPath "C:\Logs" -KeepTempFiles
```

### Standalone Script Usage (Legacy)

```powershell
# Run the full hydration process
.\Invoke-IntuneHydration.ps1

# Skip specific components
.\Invoke-IntuneHydration.ps1 -SkipEnrollment -SkipGroups

# Specify a tenant ID
.\Invoke-IntuneHydration.ps1 -TenantId "your-tenant-id-here"
```

For detailed usage examples, see [EXAMPLES.md](EXAMPLES.md) and [QUICKSTART.md](QUICKSTART.md).

### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `-SkipPolicies` | Switch | Skip importing OpenIntuneBaseline policies |
| `-SkipCompliance` | Switch | Skip importing compliance baselines |
| `-SkipSecurityBaselines` | Switch | Skip importing Microsoft Security Baselines |
| `-SkipEnrollment` | Switch | Skip creating Autopilot and ESP profiles |
| `-SkipGroups` | Switch | Skip creating dynamic groups |
| `-SkipConditionalAccess` | Switch | Skip importing Conditional Access policies |
| `-TenantId` | String | Azure AD Tenant ID (optional) |

## What Gets Created

### Dynamic Groups

**OS-based Groups:**
- All Windows Devices
- All iOS Devices
- All Android Devices
- All macOS Devices

**Manufacturer-based Groups:**
- Devices - Microsoft
- Devices - Dell
- Devices - HP
- Devices - Lenovo

**Autopilot Groups:**
- Autopilot Devices
- Non-Autopilot Windows Devices

**Compliance Groups:**
- Compliant Devices
- Non-Compliant Devices

**Model-based Groups (examples):**
- Devices - Surface Laptop
- Devices - Surface Pro

### Compliance Policies

Multi-platform compliance policies with security baselines:
- Windows - Compliance Baseline
- iOS - Compliance Baseline
- Android - Compliance Baseline
- macOS - Compliance Baseline

### Enrollment Profiles

- **Autopilot Profile**: Corporate Autopilot configuration with device naming and OOBE customization
- **ESP Profile**: Enrollment Status Page with installation tracking and timeout settings

### Conditional Access Policies (All Disabled by Default)

1. **CA001**: Require MFA for Administrators
2. **CA002**: Block Legacy Authentication
3. **CA003**: Require MFA for Azure Management
4. **CA004**: Require Compliant or Hybrid Joined Device
5. **CA005**: Block Access from Unknown Locations
6. **CA006**: Require App Protection Policy for Mobile
7. **CA007**: Require MFA for All Users
8. **CA008**: Block Access from Risky Sign-ins
9. **CA009**: Require Terms of Use
10. **CA010**: Require Password Change for Risky Users

⚠️ **Important**: All Conditional Access policies are created in a disabled state. Review, test, and enable them individually based on your organization's requirements.

### Security Baselines

- Windows Security Baseline
- Edge Security Baseline
- Windows 365 Security Baseline
- Microsoft Defender for Endpoint Baseline

## Configuration

The `Config.json` file allows you to customize various settings:

```json
{
  "HydrationSettings": {
    "Description": "Configuration file for Intune Hydration Kit",
    "Version": "1.0.0"
  },
  "Features": {
    "ImportPolicies": true,
    "ImportCompliance": true,
    "ImportSecurityBaselines": true,
    "CreateEnrollmentProfiles": true,
    "CreateDynamicGroups": true,
    "ImportConditionalAccess": true
  }
}
```

## Logging

Logs are automatically saved to the `Logs` directory with timestamps:
```
Logs/IntuneHydration_YYYYMMDD_HHMMSS.log
```

The log includes:
- Timestamp for each operation
- Success/failure status
- Warnings and errors
- Summary of created resources

## Source Repositories

This script leverages configurations from:
- **OpenIntuneBaseline**: [https://github.com/SkipToTheEndpoint/OpenIntuneBaseline](https://github.com/SkipToTheEndpoint/OpenIntuneBaseline)
- **IntuneManagement**: [https://github.com/Micke-K/IntuneManagement](https://github.com/Micke-K/IntuneManagement)

## Best Practices

1. **Test in a non-production environment first**
2. **Review all policies before enabling** (especially Conditional Access)
3. **Customize device naming templates** in the Autopilot profile
4. **Adjust compliance requirements** based on your organization's needs
5. **Review dynamic group membership rules** to ensure they match your environment
6. **Monitor the Logs directory** for any warnings or errors during execution

## Troubleshooting

### Common Issues

**Authentication Fails:**
- Ensure you have the required Microsoft Graph permissions
- Check if your account has Intune Administrator or Global Administrator role

**Module Installation Fails:**
- Run PowerShell as Administrator
- Manually install required modules: `Install-Module Microsoft.Graph -Scope CurrentUser`

**Git Clone Fails:**
- Ensure Git is installed and in your PATH
- Check internet connectivity and proxy settings

**Policies Not Importing:**
- Verify Microsoft Graph connectivity
- Check that you have write permissions in Intune
- Review the log file for specific errors

## Security Considerations

- The script uses Microsoft Graph API with delegated permissions
- No credentials are stored in the script or configuration files
- All Conditional Access policies are created in a disabled state
- Review and test each policy before enabling in production

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## License

This project is provided as-is for use in your Intune environment.

## Disclaimer

This script creates policies and configurations in your Intune tenant. Always test in a non-production environment first. The authors are not responsible for any issues that may arise from using this script.

## Version History

- **1.0.0** - Initial release
  - OpenIntuneBaseline policy import
  - Compliance baseline pack
  - Microsoft Security Baselines
  - Autopilot and ESP profiles
  - Dynamic groups
  - Conditional Access starter pack
