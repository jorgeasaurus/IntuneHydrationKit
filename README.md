# Intune Hydration Kit

<p align="center">
  <img src="media/IHTLogoClearLight.png" alt="Intune Hydration Kit Logo" width="500">
</p>

<p align="center">
  <strong>Automate your Microsoft Intune tenant configuration with best-practice defaults</strong>
</p>

<p align="center">
  <a href="https://www.powershellgallery.com/packages/IntuneHydrationKit"><img src="https://img.shields.io/powershellgallery/v/IntuneHydrationKit?label=PSGallery&color=blue" alt="PowerShell Gallery Version"></a>
  <a href="https://www.powershellgallery.com/packages/IntuneHydrationKit"><img src="https://img.shields.io/powershellgallery/dt/IntuneHydrationKit?label=Downloads&color=green" alt="PowerShell Gallery Downloads"></a>
  <a href="https://github.com/jorgeasaurus/Intune-Hydration-Kit/blob/main/LICENSE"><img src="https://img.shields.io/github/license/jorgeasaurus/Intune-Hydration-Kit" alt="License"></a>
</p>

<p align="center">
  <a href="#installation">Installation</a> •
  <a href="#quick-start">Quick Start</a> •
  <a href="#configuration">Configuration</a> •
  <a href="#safety-features">Safety Features</a> •
  <a href="#troubleshooting">Troubleshooting</a>
</p>

---

## Overview

The Intune Hydration Kit is a PowerShell module that bootstraps Microsoft Intune tenants with boilerplate configurations. It automatically downloads the latest [OpenIntuneBaseline](https://github.com/SkipToTheEndpoint/OpenIntuneBaseline) policies and imports them alongside compliance policies, dynamic groups, and more—turning hours of manual configuration into a single command.

<p align="center">
  <img src="media/SampleOutput.png" alt="Sample Output" width="800">
</p>

### What Gets Created

| Category | Count | Description |
|----------|-------|-------------|
| Dynamic Groups | 31 | Device and user targeting groups (OS, manufacturer, Autopilot, ownership, licensing) |
| Static Groups | 2 | Update ring groups (Pilot, UAT) for manual membership |
| Device Filters | 12 | Platform and manufacturer-based filters |
| Security Baselines | 70+ | OpenIntuneBaseline policies (Windows, macOS) |
| Compliance Policies | 10 | Multi-platform compliance (Windows, macOS, iOS, Android, Linux) |
| App Protection | 8 | MAM policies following [Microsoft's App Protection Framework](https://learn.microsoft.com/en-us/intune/intune-service/apps/app-protection-framework) (Level 1-3 for iOS and Android) |
| Mobile Apps | 7 | Microsoft Store apps, macOS apps (Company Portal, Edge, etc.) |
| Enrollment Profiles | 3 | Autopilot deployment + Enrollment Status Page |
| Conditional Access | 14 | Starter pack policies (created disabled) |

---

## Important Warnings

> **⚠️ READ BEFORE USE**

### This Tool Can Modify Your Production Environment

- **Creates objects** in your Intune tenant (policies, groups, filters)
- **Can delete objects** when run with delete mode enabled
- **Modifies Conditional Access** policies (though always created disabled)

### Recommendations

1. **Test in a non-production tenant first** - Use a dev/test tenant before running against production
2. **Always preview changes first** - Use `-WhatIf` in parameter or settings mode
3. **Review the configuration** - Understand what will be imported before running
4. **Have a rollback plan** - Know how to manually remove configurations if needed
5. **Backup existing configurations** - Export current settings before running

### Deletion Safety

When using delete mode (`-Delete` parameter or `"delete": true` in settings), the kit will **only delete objects that it created**:

- Objects must have `"Imported by Intune-Hydration-Kit"` in their description
- Conditional Access policies must also be in `disabled` state to be deleted
- Manually created objects with the same names will NOT be deleted

---

## Features

- **Idempotent** - Safe to run multiple times; skips existing configurations
- **Dry-Run Mode** - Preview changes with PowerShell `-WhatIf` before applying
- **Safe Deletion** - Only removes objects created by this kit
- **Multi-Platform** - Supports Windows, macOS, iOS, Android, and Linux
- **OpenIntuneBaseline Integration** - Automatically downloads latest community baselines
- **Detailed Logging** - Full audit trail of all operations
- **Summary Reports** - Markdown and JSON reports of all changes

---

## Prerequisites

### Required PowerShell Version

- PowerShell 7.0 or later

### Required Modules

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
```

> **Note:** This module uses `Invoke-MgGraphRequest` for all Graph API calls, so only the Authentication module is required.

### Required Permissions

The authenticated user/app needs these Microsoft Graph permissions:

- `DeviceManagementConfiguration.ReadWrite.All`
- `DeviceManagementServiceConfig.ReadWrite.All`
- `DeviceManagementManagedDevices.ReadWrite.All`
- `DeviceManagementScripts.ReadWrite.All`
- `DeviceManagementApps.ReadWrite.All`
- `Group.ReadWrite.All`
- `Policy.Read.All`
- `Policy.ReadWrite.ConditionalAccess`
- `Application.Read.All`
- `Directory.ReadWrite.All`
- `LicenseAssignment.Read.All`
- `Organization.Read.All`

---

## Installation

### Option A: PowerShell Gallery (Recommended)

Install directly from the PowerShell Gallery:

```powershell
Install-Module -Name IntuneHydrationKit -Scope CurrentUser
```

To update to the latest version:

```powershell
Update-Module -Name IntuneHydrationKit
```

### Option B: Clone from GitHub

For development or to use the latest unreleased changes:

```powershell
git clone https://github.com/jorgeasaurus/Intune-Hydration-Kit.git
cd Intune-Hydration-Kit
Import-Module ./IntuneHydrationKit.psd1
```

---

## Quick Start

The kit supports two invocation methods: **parameters** (recommended) or **settings file** (for complex configurations).

### Using the PSGallery Module

After installing from PSGallery, use the `Invoke-IntuneHydration` function directly:

```powershell
# Preview all targets with interactive auth
Invoke-IntuneHydration -TenantId "your-tenant-id" `
    -Interactive `
    -Create `
    -All `
    -WhatIf

# Run specific targets only
Invoke-IntuneHydration -TenantId "your-tenant-id" `
    -Interactive `
    -Create `
    -ComplianceTemplates `
    -DynamicGroups `
    -DeviceFilters

# Use service principal authentication
$secret = ConvertTo-SecureString "your-secret" -AsPlainText -Force
Invoke-IntuneHydration -TenantId "your-tenant-id" `
    -ClientId "app-id" `
    -ClientSecret $secret `
    -Create `
    -All

# Use a settings file for complex configurations
Invoke-IntuneHydration -SettingsPath ./settings.json

# Preview with settings file
Invoke-IntuneHydration -SettingsPath ./settings.json -WhatIf
```

### Using the Cloned Repository

If you cloned the repository, use the wrapper script:

```powershell
# Preview all targets with interactive auth
./Invoke-IntuneHydration.ps1 -TenantId "your-tenant-id" `
    -Interactive `
    -Create `
    -All `
    -WhatIf

# Run specific targets only
./Invoke-IntuneHydration.ps1 -TenantId "your-tenant-id" `
    -Interactive `
    -Create `
    -ComplianceTemplates `
    -DynamicGroups `
    -DeviceFilters

# Use service principal authentication
$secret = ConvertTo-SecureString "your-secret" -AsPlainText -Force
./Invoke-IntuneHydration.ps1 -TenantId "your-tenant-id" `
    -ClientId "app-id" `
    -ClientSecret $secret `
    -Create `
    -All
```

### Using a Settings File

For complex or repeated configurations, use a settings file:

#### 1. Create Your Settings File

```powershell
# If using cloned repo
Copy-Item settings.example.json settings.json

# If using PSGallery module, create your own settings.json
```

Edit `settings.json` with your tenant details:

```json
{
    "tenant": {
        "tenantId": "your-tenant-id-here",
        "tenantName": "yourtenant.onmicrosoft.com"
    },
    "authentication": {
        "mode": "interactive"
    },
    "options": {
        "dryRun": false,
        "create": true,
        "delete": false,
        "force": false
    }
}
```

#### 2. Preview Changes (Recommended First Step)

```powershell
# PSGallery module
Invoke-IntuneHydration -SettingsPath ./settings.json -WhatIf

# Cloned repo
./Invoke-IntuneHydration.ps1 -SettingsPath ./settings.json -WhatIf
```

#### 3. Run the Hydration

```powershell
# PSGallery module
Invoke-IntuneHydration -SettingsPath ./settings.json

# Cloned repo
./Invoke-IntuneHydration.ps1 -SettingsPath ./settings.json
```

---

## Configuration

### Settings File Options

#### Tenant Configuration

```json
"tenant": {
    "tenantId": "00000000-0000-0000-0000-000000000000",
    "tenantName": "contoso.onmicrosoft.com"
}
```

#### Authentication Modes

The kit supports two authentication methods:

| Method | Use Case | Requirements |
|--------|----------|--------------|
| Interactive | Manual runs, testing | User with required permissions |
| Client Secret | Automation, CI/CD | App registration with client secret |

**Interactive (recommended for testing):**

```json
"authentication": {
    "mode": "interactive",
    "environment": "Global"
}
```

Uses browser-based login. Best for manual runs and initial testing.

**Client Secret (for automation):**

```json
"authentication": {
    "mode": "clientSecret",
    "clientId": "00000000-0000-0000-0000-000000000000",
    "clientSecret": "your-client-secret-value",
    "environment": "Global"
}
```

Uses app registration credentials. Best for unattended/automated runs.

> **Security Note:** Store client secrets securely. Consider using Azure Key Vault or environment variables instead of plaintext in settings files.

**Supported Cloud Environments:**

| Environment | Description |
|-------------|-------------|
| `Global` | Commercial/Public cloud (default) |
| `USGov` | US Government (GCC High) |
| `USGovDoD` | US Government (DoD) |
| `Germany` | Germany sovereign cloud |
| `China` | China sovereign cloud (21Vianet) |

#### Operation Modes

| Option | Description |
|--------|-------------|
| `dryRun` | Preview changes without applying (same as `-WhatIf`) |
| `create` | Create new configurations |
| `delete` | Delete existing kit-created configurations |
| `force` | Skip confirmation prompt when running delete mode |

**Create mode (default):**

```json
"options": {
    "create": true,
    "delete": false
}
```

**Delete mode (cleanup):**

```json
"options": {
    "create": false,
    "delete": true,
    "force": false
}
```

#### Selective Targets (create or delete)

Enable or disable specific configuration types (used for both create and delete workflows):

```json
"imports": {
    "openIntuneBaseline": true,
    "complianceTemplates": true,
    "appProtection": true,
    "notificationTemplates": true,
    "enrollmentProfiles": true,
    "dynamicGroups": true,
    "staticGroups": true,
    "deviceFilters": true,
    "conditionalAccess": true,
    "mobileApps": true
}
```

---

## Command-Line Parameters

The kit supports two mutually exclusive invocation modes:

1. **Settings File Mode**: Use `-SettingsPath` to load all configuration from a JSON file
2. **Parameter Mode**: Use `-TenantId` with `-Interactive` or `-ClientId`/`-ClientSecret`

These modes cannot be combined - choose one or the other.

### Tenant Parameters (Parameter Mode Only)

| Parameter | Type | Description |
|-----------|------|-------------|
| `-TenantId` | String | Azure AD tenant ID (GUID). Required for parameter mode. |
| `-TenantName` | String | Tenant name for display purposes |

### Authentication Parameters (Parameter Mode Only)

| Parameter | Type | Description |
|-----------|------|-------------|
| `-Interactive` | Switch | Use interactive (browser-based) authentication |
| `-ClientId` | String | Application ID for service principal auth |
| `-ClientSecret` | SecureString | Client secret for service principal auth |
| `-Environment` | String | Cloud environment: `Global`, `USGov`, `USGovDoD`, `Germany`, `China` (default: Global) |

### Options Parameters (Parameter Mode Only)

| Parameter | Type | Description |
|-----------|------|-------------|
| `-Create` | Switch | Enable creation of configurations |
| `-Delete` | Switch | Enable deletion of kit-created objects |
| `-Force` | Switch | Skip confirmation when running in delete mode |
| `-VerboseOutput` | Switch | Enable verbose logging |
| `-WhatIf` | Switch | PowerShell built-in preview mode (applies to any parameter set) |

### Target Parameters (Parameter Mode Only)

| Parameter | Type | Description |
|-----------|------|-------------|
| `-All` | Switch | Enable all targets |
| `-OpenIntuneBaseline` | Switch | Process OpenIntuneBaseline policies |
| `-ComplianceTemplates` | Switch | Process compliance policies |
| `-AppProtection` | Switch | Process app protection policies |
| `-NotificationTemplates` | Switch | Process notification templates |
| `-EnrollmentProfiles` | Switch | Process Autopilot/ESP profiles |
| `-DynamicGroups` | Switch | Process dynamic groups |
| `-StaticGroups` | Switch | Process static (assigned) groups |
| `-DeviceFilters` | Switch | Process device filters |
| `-ConditionalAccess` | Switch | Process CA starter pack |
| `-MobileApps` | Switch | Process mobile app templates |

### OpenIntuneBaseline Parameters (Parameter Mode Only)

| Parameter | Type | Description |
|-----------|------|-------------|
| `-BaselineRepoUrl` | String | GitHub repository URL |
| `-BaselineBranch` | String | Git branch to use |
| `-BaselineDownloadPath` | String | Local download path |

### Reporting Parameters (Parameter Mode Only)

| Parameter | Type | Description |
|-----------|------|-------------|
| `-ReportOutputPath` | String | Output directory for reports |
| `-ReportFormats` | String[] | Report formats: `markdown`, `json` |

### Settings File Mode Parameter

| Parameter | Type | Description |
|-----------|------|-------------|
| `-SettingsPath` | String | Path to settings JSON file. Required for settings file mode. |
| `-WhatIf` | Switch | Preview mode (same as `dryRun: true` in settings) |

---

## Safety Features

### Hydration Marker

All objects created by this kit include a marker in their description:

```
Imported by Intune-Hydration-Kit
```

This marker is used to:

- Identify objects created by this tool
- Prevent deletion of manually-created objects
- Enable safe cleanup operations

### Conditional Access Protection

Conditional Access policies receive additional protection:

- **Always created in `disabled` state** - Never automatically enabled
- **Deletion requires disabled state** - Cannot delete enabled CA policies
- **Manual review required** - You must manually enable policies after review

### WhatIf Support (Preview Mode)

All operations support PowerShell `-WhatIf` preview mode in both parameter and settings modes:

```powershell
# Parameter mode
./Invoke-IntuneHydration.ps1 -TenantId "guid" -Interactive -Create -All -WhatIf

# Settings file mode
./Invoke-IntuneHydration.ps1 -SettingsPath ./settings.json -WhatIf
```

---

## Output and Reports

### Console Output

The script provides real-time progress with colored status indicators:

- `[i]` Info - Operation details
- `[!]` Warning - Non-fatal issues
- `Created:` - New object created
- `Skipped:` - Object already exists
- `Deleted:` - Object removed

### Log Files

Detailed logs are written to the `Logs/` directory:

```plaintext
Logs/hydration-20241127-143052.log
```

### Summary Reports

After each run, reports are generated in the `Reports/` directory:

- `Hydration-Summary.md` - Human-readable markdown report
- `Hydration-Summary.json` - Machine-readable JSON for automation

---

## Troubleshooting

### Common Issues

**"The term 'Invoke-MgGraphRequest' is not recognized"**

```powershell
# Install required modules
Install-Module Microsoft.Graph.Authentication -Force
```

**"Insufficient privileges"**

- Ensure you have Global Administrator or Intune Administrator role
- Check that all required Graph permissions are consented

**"No active Intune license found"**

- Verify Intune licenses are assigned in the tenant
- Check for INTUNE_A, INTUNE_EDU, or EMS license

**Objects not being deleted**

- Verify the object has "Imported by Intune-Hydration-Kit" in its description
- For CA policies, ensure the policy is in `disabled` state

### Debug Mode

Enable verbose logging in settings:

```json
"options": {
    "verbose": true
}
```

Or use PowerShell's verbose preference:

```powershell
$VerbosePreference = "Continue"
./Invoke-IntuneHydration.ps1 -SettingsPath ./settings.json
```

---

## Project Structure

```plaintext
Intune-Hydration-Kit/
├── Invoke-IntuneHydration.ps1    # Wrapper script (backward compatibility)
├── IntuneHydrationKit.psd1       # Module manifest
├── IntuneHydrationKit.psm1       # Module loader
├── build.ps1                      # Build bootstrap script
├── IntuneHydrationKit.build.ps1  # InvokeBuild tasks
├── settings.example.json          # Example configuration
├── Public/                        # Exported functions
│   ├── Invoke-IntuneHydration.ps1 # Main orchestrator function
│   ├── Connect-IntuneHydration.ps1
│   ├── Import-IntuneBaseline.ps1
│   ├── Import-IntuneCompliancePolicy.ps1
│   ├── Import-IntuneMobileApp.ps1
│   └── ...
├── Private/                       # Internal helper functions
├── Scripts/                       # Helper scripts
│   └── New-MobileAppTemplate.ps1  # Generate mobile app JSON templates
├── Templates/                     # Configuration templates
│   ├── Compliance/
│   ├── ConditionalAccess/
│   ├── DynamicGroups/
│   ├── StaticGroups/
│   ├── MobileApps/
│   └── ...
├── Tests/                         # Pester tests
├── Logs/                          # Execution logs
└── Reports/                       # Generated reports
```

---

## Creating Mobile App Templates

The kit includes a helper script to generate JSON templates for mobile apps. This makes it easy to add new apps to your hydration workflow.

### Using the Template Generator

```powershell
# Create a Microsoft Store (winGetApp) template
.\Scripts\New-MobileAppTemplate.ps1 -AppType winGetApp `
    -DisplayName "Company Portal" `
    -PackageIdentifier "9WZDNCRFJ3PZ" `
    -Publisher "Microsoft Corporation" `
    -PrivacyUrl "http://go.microsoft.com/fwlink/?LinkID=316999" `
    -IconPath ".\Templates\MobileApps\Microsoft-IntuneCompanyPortal.png"

# Create a macOS Edge template
.\Scripts\New-MobileAppTemplate.ps1 -AppType macOSMicrosoftEdgeApp `
    -DisplayName "Microsoft Edge for macOS" `
    -Publisher "Microsoft" `
    -Channel stable

# Create Microsoft 365 Apps for Windows
.\Scripts\New-MobileAppTemplate.ps1 -AppType officeSuiteApp `
    -DisplayName "Microsoft 365 Apps for Windows" `
    -Publisher "Microsoft"
```

### Supported App Types

| App Type | Description | Required Parameters |
|----------|-------------|---------------------|
| `winGetApp` | Microsoft Store apps | `-PackageIdentifier` |
| `macOSMicrosoftEdgeApp` | Edge for macOS | `-Channel` (stable/beta/dev) |
| `macOSOfficeSuiteApp` | Microsoft 365 for macOS | None |
| `officeSuiteApp` | Microsoft 365 for Windows | None |

### Finding Package Identifiers

For Microsoft Store apps, you can find the package identifier in the store URL or by searching:

- Company Portal: `9WZDNCRFJ3PZ`
- PowerShell: `9MZ1SNWT0N5D`
- Visual Studio Code: `XP9KHM4BK9FZ7Q`
- Adobe Acrobat Reader: `XPDP273C0XHQH2`

---

## Changelog

### v0.2.0

- **New Feature:** Static Groups support
  - Added `New-IntuneStaticGroup` function for creating assigned security groups
  - Added `-StaticGroups` parameter to `Invoke-IntuneHydration`
  - Added `staticGroups` option to settings file imports section
  - Static group templates stored in `Templates/StaticGroups/` directory
  - Includes Update Ring groups (Pilot, UAT) for Windows Update for Business
- **New Feature:** Expanded Dynamic Groups (12 → 30+)
  - Added ownership groups (Corporate, BYOD)
  - Added user-based groups (Intune Licensed Users, Update Ring Broad)
  - Added platform-specific ownership groups (macOS, iPhone, iPad, Android)
  - Added Android Enterprise groups (Work Profile, Fully Managed)
  - Added Windows ConfigMgr Managed devices group
- **New Feature:** Mobile Apps support
  - Added `Import-IntuneMobileApp` function to import mobile app templates
  - Added `-MobileApps` parameter to `Invoke-IntuneHydration`
  - Added `mobileApps` option to settings file imports section
  - Added `Scripts/New-MobileAppTemplate.ps1` helper to generate mobile app JSON templates
  - Supports winGetApp (Microsoft Store), macOSMicrosoftEdgeApp, macOSOfficeSuiteApp, officeSuiteApp types
  - Mobile app templates stored in `Templates/MobileApps/` directory
- **New Feature:** PowerShell Gallery publishing support
- Module now installable via `Install-Module IntuneHydrationKit`
- Added `Invoke-IntuneHydration` as exported module function
- Backward compatible wrapper script for users who clone the repository
- InvokeBuild-based build system for CI/CD
- GitHub Actions workflows for automated testing and publishing
- Added Pester tests for main orchestrator function
- Fixed PSScriptAnalyzer warnings (variable naming conflicts)
- Fixed notification template deletion (now matches by template name)

### v0.1.8

- **New Feature:** Full parameter-based invocation support
- Two mutually exclusive modes: settings file (`-SettingsPath`) or parameters (`-TenantId` + auth)
- Added `-All` switch to enable all targets at once
- Added PowerShell `-WhatIf` preview mode support across invocation modes
- Added parameters for all configuration options (tenant, auth, targets, reporting)
- Settings file mode continues to work unchanged
- Added Windows Driver Update license pre-check to avoid 403 errors when importing driver update profiles without required licensing (Windows E3/E5, M365 Business Premium)
- Added `LicenseAssignment.Read.All` scope for license validation checks
- Added `Organization.Read.All` scope for tenant organization details

### v0.1.4

- Added `DeviceManagementScripts.ReadWrite.All` scope for custom compliance scripts (required after Microsoft Graph API permission changes)
- Added `Application.Read.All` scope for Conditional Access policies targeting specific applications
- Added `Policy.Read.All` scope for querying existing Conditional Access policies
- Updated prerequisite checks to validate Graph permission scopes
- Removed MDM authority check from prerequisites

### v0.1.3

- Fixed image paths in README.md

### v0.1.2

- Refactored code structure for improved readability and maintainability

### v0.1.1

- Updated module manifest with correct author and company details

### v0.1.0 - Initial Release

- OpenIntuneBaseline integration (auto-downloads latest policies)
- Compliance policy templates (Windows, macOS, iOS, Android, Linux)
- App protection policies (Android/iOS MAM)
- Dynamic groups and device filters
- Enrollment profiles (Autopilot, ESP)
- Conditional Access starter pack (always created disabled)
- Safe deletion (only removes kit-created objects)
- Multi-cloud support (Global, USGov, USGovDoD, Germany, China)
- WhatIf/dry-run mode
- Detailed logging and reporting

---

## Acknowledgments

- [OpenIntuneBaseline](https://github.com/SkipToTheEndpoint/OpenIntuneBaseline) by SkipToTheEndpoint - Community-driven Intune security baselines
- Microsoft Graph PowerShell SDK team

---

## Disclaimer

This tool is provided "as-is" without warranty of any kind. Always test in a non-production environment first. The authors are not responsible for any unintended changes to your Intune tenant. Review all configurations before enabling in production.
