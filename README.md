# Intune Hydration Kit

> **⚠️ IMPORTANT**: This script provides a comprehensive **framework and templates** for Intune hydration. The current version includes all the structure, data models, and logic for creating policies, with Microsoft Graph API calls documented as comments. Users can uncomment and customize these API calls based on their specific needs, or use this as a reference for building their own automation. This approach provides maximum flexibility while demonstrating best practices for Intune configuration management.

Quick way to import starter configurations into Microsoft Intune. This PowerShell script automates the process of "hydrating" a new or existing Intune tenant with best-practice configurations, policies, profiles, and groups.

## Overview

The Intune Hydration Kit imports and configures:

- **OpenIntuneBaseline Policies**: All configuration policies from the OpenIntuneBaseline repository
- **Compliance Baselines**: Multi-platform compliance policies (Windows, iOS, Android, macOS)
- **Microsoft Security Baselines**: Windows, Edge, Windows 365, and Defender for Endpoint baselines
- **Enrollment Profiles**: Autopilot and Enrollment Status Page (ESP) profiles
- **Dynamic Groups**: Automated grouping by OS, manufacturer, model, Autopilot status, and compliance state
- **Conditional Access Policies**: 10-policy starter pack (all disabled by default for safe deployment)

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

1. Clone this repository:
```powershell
git clone https://github.com/jorgeasaurus/Intune-Hydration-Kit.git
cd Intune-Hydration-Kit
```

2. Review and customize `Config.json` (optional)

## Usage

### Basic Usage

Run the full hydration process:
```powershell
.\Invoke-IntuneHydration.ps1
```

You will be prompted to authenticate with Microsoft Graph.

### Advanced Usage

Skip specific components:
```powershell
# Skip enrollment profiles and groups
.\Invoke-IntuneHydration.ps1 -SkipEnrollment -SkipGroups

# Skip all except Conditional Access
.\Invoke-IntuneHydration.ps1 -SkipPolicies -SkipCompliance -SkipSecurityBaselines -SkipEnrollment -SkipGroups

# Specify a tenant ID
.\Invoke-IntuneHydration.ps1 -TenantId "your-tenant-id-here"
```

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
