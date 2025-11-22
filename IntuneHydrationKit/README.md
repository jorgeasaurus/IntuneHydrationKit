# IntuneHydrationKit PowerShell Module

A PowerShell module for hydrating Microsoft Intune tenants with best-practice policies, compliance baselines, security settings, enrollment profiles, dynamic groups, and Conditional Access policies.

## Installation

### From Local Directory

```powershell
# Import the module
Import-Module .\IntuneHydrationKit\IntuneHydrationKit.psd1

# Or install to user modules folder
Copy-Item -Path .\IntuneHydrationKit -Destination "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\" -Recurse
Import-Module IntuneHydrationKit
```

### From PowerShell Gallery (Future)

```powershell
Install-Module -Name IntuneHydrationKit -Scope CurrentUser
Import-Module IntuneHydrationKit
```

## Prerequisites

- PowerShell 5.1 or higher (including PowerShell 7+)
- Git installed and in PATH
- Internet connectivity
- Intune Administrator or Global Administrator role
- Microsoft Graph PowerShell modules (auto-installed):
  - Microsoft.Graph.Authentication
  - Microsoft.Graph.DeviceManagement
  - Microsoft.Graph.Groups
  - Microsoft.Graph.Identity.SignIns

## Quick Start

```powershell
# Import the module
Import-Module IntuneHydrationKit

# Run full hydration
Invoke-IntuneHydration

# Run with specific options
Invoke-IntuneHydration -SkipEnrollment -SkipGroups -LogPath "C:\Logs"

# Keep temporary files for review
Invoke-IntuneHydration -KeepTempFiles
```

## Available Functions

### Public Functions

| Function | Description |
|----------|-------------|
| `Invoke-IntuneHydration` | Main orchestrator - runs complete hydration process |
| `Import-IntuneOpenBaseline` | Imports OpenIntuneBaseline policies from GitHub |
| `Import-IntuneComplianceBaselines` | Creates compliance policy templates (Windows, iOS, Android, macOS) |
| `Import-IntuneSecurityBaselines` | Imports Microsoft Security Baselines |
| `New-IntuneEnrollmentProfiles` | Creates Autopilot and ESP enrollment profile templates |
| `New-IntuneDynamicGroups` | Creates 14 dynamic groups for device management |
| `Import-IntuneConditionalAccessPolicies` | Creates 10 CA policy templates (all disabled) |

### Private Functions

Private helper functions (not exported):
- `Write-IntuneLog` - Logging functionality
- `Test-IntunePrerequisites` - Validates prerequisites
- `Connect-IntuneGraph` - Microsoft Graph authentication
- `Get-IntuneGitHubRepository` - GitHub repository operations

## Usage Examples

### Example 1: Complete Tenant Hydration

```powershell
Invoke-IntuneHydration
```

### Example 2: Selective Component Deployment

```powershell
# Only create groups and compliance policies
Invoke-IntuneHydration -SkipPolicies -SkipSecurityBaselines -SkipEnrollment -SkipConditionalAccess
```

### Example 3: Individual Function Usage

```powershell
# Import only compliance baselines
Import-IntuneComplianceBaselines

# Create only dynamic groups
New-IntuneDynamicGroups

# Import only Conditional Access policies
Import-IntuneConditionalAccessPolicies
```

### Example 4: Custom Logging

```powershell
Invoke-IntuneHydration -LogPath "D:\IntuneHydrationLogs" -KeepTempFiles
```

## What Gets Created

### Dynamic Groups (14 total)

**OS-based (4):**
- All Windows Devices
- All iOS Devices
- All Android Devices
- All macOS Devices

**Manufacturer-based (4):**
- Devices - Microsoft
- Devices - Dell
- Devices - HP
- Devices - Lenovo

**Autopilot-based (2):**
- Autopilot Devices
- Non-Autopilot Windows Devices

**Compliance-based (2):**
- Compliant Devices
- Non-Compliant Devices

**Model-based (2):**
- Devices - Surface Laptop
- Devices - Surface Pro

### Compliance Policies (4)

- Windows - Compliance Baseline
- iOS - Compliance Baseline
- Android - Compliance Baseline
- macOS - Compliance Baseline

### Enrollment Profiles (2)

- Corporate Autopilot Profile
- Corporate ESP (Enrollment Status Page) Profile

### Conditional Access Policies (10)

1. CA001: Require MFA for Administrators
2. CA002: Block Legacy Authentication
3. CA003: Require MFA for Azure Management
4. CA004: Require Compliant or Hybrid Joined Device
5. CA005: Require MFA from Unknown Locations
6. CA006: Require App Protection Policy for Mobile
7. CA007: Require MFA for All Users
8. CA008: Block Access from Risky Sign-ins
9. CA009: Require Terms of Use
10. CA010: Require Password Change for Risky Users

⚠️ **Important**: All CA policies are created in **disabled** state for safety.

### Security Baselines (4)

- Windows Security Baseline
- Edge Security Baseline
- Windows 365 Security Baseline
- Microsoft Defender for Endpoint Baseline

## Framework Approach

> **Note**: This module provides a comprehensive framework and templates for Intune hydration. The current version includes all the structure, data models, and logic for creating policies, with Microsoft Graph API calls documented as comments within the code. Users can uncomment and customize these API calls based on their specific needs, or use this as a reference for building their own automation.

## Parameters Reference

### Invoke-IntuneHydration Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `-SkipPolicies` | Switch | Skip OpenIntuneBaseline import |
| `-SkipCompliance` | Switch | Skip compliance baselines |
| `-SkipSecurityBaselines` | Switch | Skip security baselines |
| `-SkipEnrollment` | Switch | Skip Autopilot & ESP profiles |
| `-SkipGroups` | Switch | Skip dynamic groups |
| `-SkipConditionalAccess` | Switch | Skip CA policies |
| `-TenantId` | String | Specify Azure AD Tenant ID |
| `-LogPath` | String | Custom log file location |
| `-KeepTempFiles` | Switch | Don't delete temporary repositories |

## Module Structure

```
IntuneHydrationKit/
├── IntuneHydrationKit.psd1          # Module manifest
├── IntuneHydrationKit.psm1          # Root module file
├── Private/                         # Private helper functions
│   ├── Connect-IntuneGraph.ps1
│   ├── Get-IntuneGitHubRepository.ps1
│   ├── Test-IntunePrerequisites.ps1
│   └── Write-IntuneLog.ps1
└── Public/                          # Public exported functions
    ├── Import-IntuneComplianceBaselines.ps1
    ├── Import-IntuneConditionalAccessPolicies.ps1
    ├── Import-IntuneOpenBaseline.ps1
    ├── Import-IntuneSecurityBaselines.ps1
    ├── Invoke-IntuneHydration.ps1
    ├── New-IntuneDynamicGroups.ps1
    └── New-IntuneEnrollmentProfiles.ps1
```

## Logging

Logs are automatically created in the module's `Logs` directory (or custom path if specified):

```
Logs/IntuneHydration_YYYYMMDD_HHMMSS.log
```

Log levels: INFO, WARNING, ERROR, SUCCESS

## Source Repositories

This module integrates with:
- **OpenIntuneBaseline**: https://github.com/SkipToTheEndpoint/OpenIntuneBaseline
- **IntuneManagement**: https://github.com/Micke-K/IntuneManagement

## Troubleshooting

### Common Issues

**Module Not Found:**
```powershell
# Ensure module is in a valid PowerShell module path
$env:PSModulePath -split ';'

# Install to user modules folder
Copy-Item -Path .\IntuneHydrationKit -Destination "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\" -Recurse
```

**Prerequisites Check Fails:**
```powershell
# Manually install required modules
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Install-Module Microsoft.Graph.DeviceManagement -Scope CurrentUser
Install-Module Microsoft.Graph.Groups -Scope CurrentUser
Install-Module Microsoft.Graph.Identity.SignIns -Scope CurrentUser
```

**Git Not Found:**
- Install Git from https://git-scm.com/
- Ensure Git is in your PATH

## Best Practices

1. **Test in non-production first** - Always test in a lab tenant
2. **Review all templates** - Understand what each function does
3. **Enable CA policies carefully** - Test each policy individually
4. **Keep logs** - Use `-LogPath` for audit trails
5. **Use `-KeepTempFiles`** - For troubleshooting or manual review of cloned repositories

## Contributing

Contributions are welcome! Please submit issues or pull requests to the GitHub repository.

## License

This project is provided as-is for use in your Intune environment.

## Version History

- **1.0.0** - Initial module release
  - PSStucco compliant module structure
  - 7 public functions
  - 4 private helper functions
  - Comprehensive parameter support
  - Cross-platform compatibility
  - Framework/template approach for maximum flexibility

## Support

For issues, questions, or feature requests, please visit:
https://github.com/jorgeasaurus/Intune-Hydration-Kit
